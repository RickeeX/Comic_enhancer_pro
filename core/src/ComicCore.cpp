#include "ComicCore.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <thread>
#include <vector>
#include <new>
#include <mutex>
#include <exception>
namespace {
constexpr uint64_t maxPixels = 100000000;
bool valid(const CEOptions &o) {
    auto in=[](float x,float a,float b){return std::isfinite(x)&&x>=a&&x<=b;};
    return in(o.brightness,-1,1)&&in(o.contrast,0,3)&&in(o.gamma,.2f,3)&&
        in(o.white_point,.2f,1)&&in(o.sharpen,0,2)&&in(o.blur,0,1)&&
        in(o.scale,.1f,2)&&in(o.crop,0,.2f)&&o.rotation>=0&&o.rotation<=3&&
        o.page>=0&&o.page<=2&&(o.levels==0||(o.levels>=2&&o.levels<=256))&&o.threads>=0&&o.threads<=64&&
        o.binarization>=0&&o.binarization<=3&&in(o.threshold,0,255)&&
        o.adaptive_radius>=1&&o.adaptive_radius<=100&&in(o.sauvola_k,0,1)&&
        o.cleanup>=0&&o.cleanup<=4&&o.cleanup_passes>=1&&o.cleanup_passes<=3&&
        o.dither>=0&&o.dither<=2&&o.blur_method>=0&&o.blur_method<=3&&
        o.filter_radius>=1&&o.filter_radius<=3&&in(o.edge_sigma,1,100)&&
        o.sharpen_method>=0&&o.sharpen_method<=1&&in(o.sharpen_threshold,0,255)&&
        o.deskew>=0&&o.deskew<=2&&in(o.deskew_limit,1,10)&&in(o.angle,-15,15);
}
struct Geometry { uint32_t x,y,w,h,rw,rh,ow,oh; };
Geometry geometry(uint32_t w,uint32_t h,const CEOptions&o) {
    uint32_t x=0;
    if(o.page) { uint32_t half=w/2; if(o.page==2){x=half;w-=half;}else w=half; }
    uint32_t cx=uint32_t(w*o.crop), cy=uint32_t(h*o.crop);
    Geometry g{x+cx,cy,std::max(1u,w-2*cx),std::max(1u,h-2*cy),0,0,0,0};
    g.rw=o.rotation%2?g.h:g.w;g.rh=o.rotation%2?g.w:g.h;
    g.ow=std::max(1u,uint32_t(std::lround(g.rw*o.scale)));
    g.oh=std::max(1u,uint32_t(std::lround(g.rh*o.scale)));return g;
}
template<class F> void rows(uint32_t h,int requested,F f) {
    unsigned n=std::min<unsigned>(requested?requested:std::min(8u,std::max(1u,std::thread::hardware_concurrency())),std::max(1u,h/64));
    std::vector<std::thread> workers;
    std::mutex failureMutex;std::exception_ptr failure;
    auto task=[&](uint32_t a,uint32_t b){
        try{f(a,b);}catch(...){std::lock_guard<std::mutex> lock(failureMutex);if(!failure)failure=std::current_exception();}
    };
    try { for(unsigned i=1;i<n;++i) workers.emplace_back([&,i]{task(h*i/n,h*(i+1)/n);}); }
    catch (...) { for(auto&t:workers)t.join(); throw; }
    task(0,h/n);for(auto&t:workers)t.join();
    if(failure)std::rethrow_exception(failure);
}
uint8_t byte(float v){return uint8_t(std::lround(std::clamp(v,0.f,255.f)));}
#include "Advanced.hpp"
}
extern "C" CEOptions ce_defaults(void) {
    CEOptions o{};o.contrast=1;o.gamma=1;o.white_point=1;o.scale=1;o.threshold=127;o.adaptive_radius=20;
    o.sauvola_k=.2f;o.cleanup_passes=1;o.filter_radius=1;o.edge_sigma=25;
    o.deskew_limit=5;return o;
}
extern "C" int ce_dimensions(uint32_t w,uint32_t h,const CEOptions*o,uint32_t*ow,uint32_t*oh){
    if(!o||!ow||!oh||!valid(*o)||!w||!h||(o->page&&w<2))return -1;
    if(uint64_t(w)*h>maxPixels)return -2;
    auto g=geometry(w,h,*o);if(uint64_t(g.ow)*g.oh>maxPixels)return -2;
    *ow=g.ow;*oh=g.oh;return 0;
}
extern "C" int ce_process(const uint8_t*src,uint32_t w,uint32_t h,const CEOptions*o,uint8_t*dst,size_t capacity){
    uint32_t ow,oh;int status=ce_dimensions(w,h,o,&ow,&oh);if(status)return status;
    if(!src||!dst||src==dst)return -1;
    if(capacity<uint64_t(ow)*oh*4)return -3;
    try {
        auto g=geometry(w,h,*o);
        int low=0,high=255;
        if(o->auto_levels){
            std::array<uint64_t,256> hist{};
            for(uint32_t y=g.y;y<g.y+g.h;++y)for(uint32_t x=g.x;x<g.x+g.w;++x){
                auto p=src+(size_t(y)*w+x)*4;hist[(54*p[0]+183*p[1]+19*p[2]+128)>>8]++;
            }
            uint64_t tail=uint64_t(g.w)*g.h/200,sum=0;
            for(;low<255;++low){sum+=hist[low];if(sum>tail)break;}
            sum=0;for(;high>0;--high){sum+=hist[high];if(sum>tail)break;}
            if(high<=low){low=0;high=255;}
        }
        std::array<uint8_t,256> lut{};
        for(int i=0;i<256;++i){
            float v=std::clamp((i-low)/float(high-low),0.f,1.f);
            v=std::clamp(((v-.5f)*o->contrast+.5f+o->brightness)/o->white_point,0.f,1.f);
            lut[i]=byte(255*std::pow(v,o->gamma));
        }
        auto sample=[&](int rx,int ry,int c){
            rx=std::clamp(rx,0,int(g.rw)-1);ry=std::clamp(ry,0,int(g.rh)-1);
            uint32_t x=rx,y=ry;
            switch(o->rotation){case 1:x=ry;y=g.h-1-rx;break;case 2:x=g.w-1-rx;y=g.h-1-ry;break;case 3:x=g.w-1-ry;y=rx;break;}
            return float(src[(size_t(g.y+y)*w+g.x+x)*4+c]);
        };
        // Pixel-only stages must not pay for rotation/clamping/interpolation.
        // This is also the exact integer sampling path for crop/quarter turns.
        const bool integerSamples=ow==g.rw&&oh==g.rh;
        const bool gray=o->grayscale||o->levels||o->binarization;
        rows(oh,o->threads,[&](uint32_t a,uint32_t b){
            if(integerSamples){
                for(uint32_t y=a;y<b;++y)for(uint32_t x=0;x<ow;++x){
                    uint32_t xx=x,yy=y;
                    switch(o->rotation){case 1:xx=y;yy=g.h-1-x;break;case 2:xx=g.w-1-x;yy=g.h-1-y;break;case 3:xx=g.w-1-y;yy=x;break;}
                    auto in=src+(size_t(g.y+yy)*w+g.x+xx)*4;
                    auto p=dst+(size_t(y)*ow+x)*4;
                    p[0]=lut[in[0]];p[1]=lut[in[1]];p[2]=lut[in[2]];
                    if(gray){auto v=luminance(p);p[0]=p[1]=p[2]=v;}p[3]=255;
                }
                return;
            }
            for(uint32_t y=a;y<b;++y)for(uint32_t x=0;x<ow;++x){
                float sx=(x+.5f)*g.rw/ow-.5f,sy=(y+.5f)*g.rh/oh-.5f;
                int ix=int(std::floor(sx)),iy=int(std::floor(sy));float fx=sx-ix,fy=sy-iy;
                auto p=dst+(size_t(y)*ow+x)*4;
                for(int c=0;c<3;++c){
                    float top=sample(ix,iy,c)*(1-fx)+sample(ix+1,iy,c)*fx;
                    float bot=sample(ix,iy+1,c)*(1-fx)+sample(ix+1,iy+1,c)*fx;
                    p[c]=lut[byte(top*(1-fy)+bot*fy)];
                }
                if(gray){uint8_t v=luminance(p);p[0]=p[1]=p[2]=v;}
                p[3]=255;
            }
        });
        float angle=o->angle;
        if(o->deskew)angle+=estimate(dst,ow,oh,o->deskew==2,o->deskew_limit);
        if(std::abs(angle)>.001f)rotateFine(dst,ow,oh,angle,o->threads);
        filter(dst,ow,oh,*o);
        reduce(dst,ow,oh,*o);
        return 0;
    }catch(...){return -4;}
}

extern "C" int ce_estimate_skew(const uint8_t*src,uint32_t w,uint32_t h,int32_t vertical,float limit,float*degrees){
    if(!src||!degrees||!w||!h||vertical<0||vertical>1||!std::isfinite(limit)||limit<1||limit>10)return -1;
    if(uint64_t(w)*h>maxPixels)return -2;
    try{*degrees=estimate(src,w,h,vertical!=0,limit);return 0;}catch(...){return -4;}
}

#include "PageCore.hpp"
