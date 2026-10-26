#include "ComicCore.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <thread>
#include <vector>
#include <new>
namespace {
constexpr uint64_t maxPixels = 40000000;
bool valid(const CEOptions &o) {
    auto in=[](float x,float a,float b){return std::isfinite(x)&&x>=a&&x<=b;};
    return in(o.brightness,-1,1)&&in(o.contrast,0,3)&&in(o.gamma,.2f,3)&&
        in(o.white_point,.2f,1)&&in(o.sharpen,0,2)&&in(o.blur,0,1)&&
        in(o.scale,.1f,2)&&in(o.crop,0,.2f)&&o.rotation>=0&&o.rotation<=3&&
        o.page>=0&&o.page<=2&&(o.levels==0||(o.levels>=2&&o.levels<=256))&&o.threads>=0&&o.threads<=64;
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
    // Joining already-created threads also makes a thread-creation failure safe.
    try { for(unsigned i=1;i<n;++i) workers.emplace_back([&,i]{f(h*i/n,h*(i+1)/n);}); }
    catch (...) { for(auto&t:workers)t.join(); throw; }
    f(0,h/n);for(auto&t:workers)t.join();
}
uint8_t byte(float v){return uint8_t(std::lround(std::clamp(v,0.f,255.f)));}
}
extern "C" CEOptions ce_defaults(void) {
    CEOptions o{};o.contrast=1;o.gamma=1;o.white_point=1;o.scale=1;return o;
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
        rows(oh,o->threads,[&](uint32_t a,uint32_t b){
            for(uint32_t y=a;y<b;++y)for(uint32_t x=0;x<ow;++x){
                float sx=(x+.5f)*g.rw/ow-.5f,sy=(y+.5f)*g.rh/oh-.5f;
                int ix=int(std::floor(sx)),iy=int(std::floor(sy));float fx=sx-ix,fy=sy-iy;
                auto p=dst+(size_t(y)*ow+x)*4;
                for(int c=0;c<3;++c){
                    float top=sample(ix,iy,c)*(1-fx)+sample(ix+1,iy,c)*fx;
                    float bot=sample(ix,iy+1,c)*(1-fx)+sample(ix+1,iy+1,c)*fx;
                    p[c]=lut[byte(top*(1-fy)+bot*fy)];
                }
                if(o->grayscale||o->levels){uint8_t v=(54*p[0]+183*p[1]+19*p[2]+128)>>8;p[0]=p[1]=p[2]=v;}
                p[3]=255;
            }
        });
        if(o->sharpen>0||o->blur>0){
            std::vector<uint8_t> copy(dst,dst+size_t(ow)*oh*4);
            rows(oh,o->threads,[&](uint32_t a,uint32_t b){
                for(uint32_t y=a;y<b;++y)for(uint32_t x=0;x<ow;++x)for(int c=0;c<3;++c){
                    int sum=0;for(int dy=-1;dy<=1;++dy)for(int dx=-1;dx<=1;++dx){
                        auto xx=std::clamp(int(x)+dx,0,int(ow)-1),yy=std::clamp(int(y)+dy,0,int(oh)-1);
                        sum+=copy[(size_t(yy)*ow+xx)*4+c]*(dx==0?2:1)*(dy==0?2:1);
                    }
                    size_t i=(size_t(y)*ow+x)*4+c;float v=copy[i],soft=sum/16.f;
                    dst[i]=byte(v+(v-soft)*o->sharpen+(soft-v)*o->blur);
                }
            });
        }
        if(o->levels){
            rows(oh,o->threads,[&](uint32_t a,uint32_t b){for(size_t i=size_t(a)*ow*4;i<size_t(b)*ow*4;i+=4){
                auto q=byte(std::round(dst[i]*(o->levels-1)/255.f)*255.f/(o->levels-1));dst[i]=dst[i+1]=dst[i+2]=q;
            }});
        }
        return 0;
    }catch(...){return -4;}
}
