// One-channel sRGB sample values. Ownership stays with the caller; scratch is
// reused within a page and never shared across concurrent page renders.
struct CEGrayWorkspace {
    std::vector<uint8_t> a,b;
    int backend=0; // 0 auto, 1 portable, 2 Accelerate (Mac only)
};
namespace {
bool graySupported(const CEOptions&o){return valid(o)&&o.deskew==0&&o.angle==0&&o.cleanup==0&&(!o.blur||o.blur_method<=1);}
#if defined(__APPLE__)
bool acceleratedGaussian(const uint8_t*src,uint32_t w,uint32_t h,int radius,int threads,CEGrayWorkspace&ws){
    ws.a.resize(size_t(w)*h);ws.b.resize(size_t(w)*h);
    std::array<int16_t,7>kernel{};kernel[0]=1;for(int i=1;i<=2*radius;++i)kernel[i]=int16_t(kernel[i-1]*(2*radius-i+1)/i);
    std::atomic<bool>ok{true};
    for(int pass=0;pass<2;++pass){
        rows(h,threads,[&](uint32_t a,uint32_t b){
            vImage_Buffer in{const_cast<uint8_t*>(pass?ws.a.data():src),h,w,w};
            vImage_Buffer out{(pass?ws.b.data():ws.a.data())+size_t(a)*w,b-a,w,w};
            const auto flags=kvImageEdgeExtend|kvImageDoNotTile;
            thread_local std::vector<uint8_t>temp;
            auto size=vImageConvolve_Planar8(&in,&out,nullptr,0,a,kernel.data(),pass?2*radius+1:1,pass?1:2*radius+1,1<<(2*radius),0,flags|kvImageGetTempBufferSize);
            if(size<0){ok=false;return;}temp.resize(size_t(size));
            if(vImageConvolve_Planar8(&in,&out,temp.data(),0,a,kernel.data(),pass?2*radius+1:1,pass?1:2*radius+1,1<<(2*radius),0,flags)!=kvImageNoError)ok=false;
        });
        if(!ok)return false;
    }
    return true;
}
#endif
template<int R> void grayGaussian(const uint8_t*src,uint32_t w,uint32_t h,int threads,CEGrayWorkspace&ws){
    constexpr int taps=2*R+1,divisor=1<<(2*R);
    std::array<int,taps> weights{};weights[0]=1;
    for(int i=1;i<taps;++i)weights[i]=weights[i-1]*(2*R-i+1)/i;
    ws.a.resize(size_t(w)*h);ws.b.resize(size_t(w)*h);
    rows(h,threads,[&](uint32_t a,uint32_t b){std::vector<uint8_t> pad(size_t(w)+2*R);
        for(uint32_t y=a;y<b;++y){auto in=src+size_t(y)*w;std::copy_n(in,w,pad.data()+R);
            std::fill_n(pad.data(),R,in[0]);std::fill_n(pad.data()+w+R,R,in[w-1]);
            for(uint32_t x=0;x<w;++x){int sum=0;for(int d=0;d<taps;++d)sum+=pad[x+d]*weights[d];
                ws.a[size_t(y)*w+x]=uint8_t((sum+divisor/2)/divisor);}
        }
    });
    rows(h,threads,[&](uint32_t a,uint32_t b){for(uint32_t y=a;y<b;++y){std::array<const uint8_t*,taps>lines{};
        for(int d=0;d<taps;++d)lines[d]=ws.a.data()+size_t(std::clamp(int(y)+d-R,0,int(h)-1))*w;
        for(uint32_t x=0;x<w;++x){int sum=0;for(int d=0;d<taps;++d)sum+=lines[d][x]*weights[d];
            ws.b[size_t(y)*w+x]=uint8_t((sum+divisor/2)/divisor);}
    }});
}
void graySmooth(const uint8_t*src,uint32_t w,uint32_t h,int radius,bool box,int threads,CEGrayWorkspace&ws){
#if defined(__APPLE__)
    if(!box&&ws.backend==2&&acceleratedGaussian(src,w,h,radius,threads,ws))return;
#endif
    if(!box){switch(radius){case 1:grayGaussian<1>(src,w,h,threads,ws);break;case 2:grayGaussian<2>(src,w,h,threads,ws);break;default:grayGaussian<3>(src,w,h,threads,ws);}return;}
    int taps=radius*2+1;ws.a.resize(size_t(w)*h);ws.b.resize(size_t(w)*h);
    rows(h,threads,[&](uint32_t a,uint32_t b){for(uint32_t y=a;y<b;++y){auto in=src+size_t(y)*w;int sum=0;
        for(int d=-radius;d<=radius;++d)sum+=in[std::clamp(d,0,int(w)-1)];
        for(uint32_t x=0;x<w;++x){ws.a[size_t(y)*w+x]=uint8_t((sum+radius)/taps);
            sum+=int(in[std::clamp(int(x)+radius+1,0,int(w)-1)])-in[std::clamp(int(x)-radius,0,int(w)-1)];}
    }});
    rows(h,threads,[&](uint32_t a,uint32_t b){std::vector<int> sums(w);
        auto add=[&](int y,int sign){auto in=ws.a.data()+size_t(std::clamp(y,0,int(h)-1))*w;for(uint32_t x=0;x<w;++x)sums[x]+=sign*in[x];};
        for(int d=-radius;d<=radius;++d)add(int(a)+d,1);
        for(uint32_t y=a;y<b;++y){for(uint32_t x=0;x<w;++x)ws.b[size_t(y)*w+x]=uint8_t((sums[x]+radius)/taps);
            add(int(y)-radius,-1);add(int(y)+radius+1,1);}
    });
}
void grayReduce(uint8_t*dst,uint32_t w,uint32_t h,const CEOptions&o,CEGrayWorkspace&ws){
    if(!o.binarization&&!o.levels)return;
    if(o.binarization){int threshold=int(o.threshold);
        if(o.binarization==2){std::array<uint64_t,256> hist{};for(size_t i=0;i<size_t(w)*h;++i)++hist[dst[i]];threshold=otsu(hist);}
        if(o.binarization!=3){rows(h,o.threads,[&](uint32_t a,uint32_t b){for(size_t i=size_t(a)*w;i<size_t(b)*w;++i)dst[i]=dst[i]<=threshold?0:255;});return;}
        ws.a.assign(dst,dst+size_t(w)*h);auto input=ws.a.data();int radius=o.adaptive_radius;
        rows(h,o.threads,[&](uint32_t begin,uint32_t end){std::vector<uint64_t>col(w),squared(w);
            auto add=[&](int y,bool remove){if(y<0||y>=int(h))return;for(uint32_t x=0;x<w;++x){uint64_t v=input[size_t(y)*w+x];if(remove){col[x]-=v;squared[x]-=v*v;}else{col[x]+=v;squared[x]+=v*v;}}};
            for(int y=std::max(0,int(begin)-radius);y<=std::min(int(h)-1,int(begin)+radius);++y)add(y,false);
            for(uint32_t y=begin;y<end;++y){if(y>begin){add(int(y)-radius-1,true);add(int(y)+radius,false);}
                uint64_t sum=0,sq=0;for(int x=0;x<=std::min(int(w)-1,radius);++x){sum+=col[x];sq+=squared[x];}
                int ny=std::min(int(h)-1,int(y)+radius)-std::max(0,int(y)-radius)+1;
                for(uint32_t x=0;x<w;++x){if(x){int l=int(x)-radius-1,r=int(x)+radius;if(l>=0){sum-=col[l];sq-=squared[l];}if(r<int(w)){sum+=col[r];sq+=squared[r];}}
                    int nx=std::min(int(w)-1,int(x)+radius)-std::max(0,int(x)-radius)+1;
                    double n=double(nx)*ny,mean=sum/n,dev=std::sqrt(std::max(0.,sq/n-mean*mean));
                    dst[size_t(y)*w+x]=input[size_t(y)*w+x]<=mean*(1+o.sauvola_k*(dev/128-1))?0:255;
                }
            }
        });return;
    }
    int levels=o.levels;auto quant=[&](float v){return byte(std::round(std::clamp(v,0.f,255.f)*(levels-1)/255.f)*255.f/(levels-1));};
    if(o.dither==2){std::vector<float>current(w+2),next(w+2);
        for(uint32_t y=0;y<h;++y){int dir=y%2?-1:1;for(uint32_t j=0;j<w;++j){int x=dir==1?int(j):int(w-1-j);float v=std::clamp(dst[size_t(y)*w+x]+current[x+1],0.f,255.f);
            auto q=quant(v);dst[size_t(y)*w+x]=q;float e=v-q;current[x+1+dir]+=e*7/16;next[x+1-dir]+=e*3/16;next[x+1]+=e*5/16;next[x+1+dir]+=e/16;}
            current.swap(next);std::fill(next.begin(),next.end(),0);}
    }else{constexpr int bayer[]={0,8,2,10,12,4,14,6,3,11,1,9,15,7,13,5};
        rows(h,o.threads,[&](uint32_t a,uint32_t b){for(uint32_t y=a;y<b;++y)for(uint32_t x=0;x<w;++x){size_t i=size_t(y)*w+x;
            float off=o.dither==1?((bayer[(y%4)*4+x%4]+.5f)/16-.5f)*255/(levels-1):0;dst[i]=quant(dst[i]+off);}});
    }
}
}
extern "C" CEGrayWorkspace*ce_gray_workspace_create(){return new(std::nothrow)CEGrayWorkspace;}
extern "C" void ce_gray_workspace_destroy(CEGrayWorkspace*w){delete w;}
extern "C" void ce_gray_workspace_backend(CEGrayWorkspace*w,int32_t backend){if(w&&backend>=0&&backend<=2)w->backend=backend;}
extern "C" int ce_gray_supported(const CEOptions*o){return o&&graySupported(*o);}
extern "C" int ce_process_gray(const uint8_t*src,uint32_t w,uint32_t h,const CEOptions*o,uint8_t*dst,size_t capacity,CEGrayWorkspace*workspace){
    uint32_t ow,oh;int status=ce_dimensions(w,h,o,&ow,&oh);if(status)return status;
    if(!src||!dst||src==dst)return -1;
    if(!graySupported(*o))return -5;
    if(capacity<size_t(ow)*oh)return -3;
    try{CEGrayWorkspace local;auto &ws=workspace?*workspace:local;auto g=geometry(w,h,*o);int low=0,high=255;
        if(o->auto_levels){std::array<uint64_t,256> hist{};for(uint32_t y=g.y;y<g.y+g.h;++y)for(uint32_t x=g.x;x<g.x+g.w;++x)++hist[src[size_t(y)*w+x]];
            uint64_t tail=uint64_t(g.w)*g.h/200,sum=0;for(;low<255;++low){sum+=hist[low];if(sum>tail)break;}sum=0;for(;high>0;--high){sum+=hist[high];if(sum>tail)break;}if(high<=low){low=0;high=255;}}
        std::array<uint8_t,256>lut{};for(int i=0;i<256;++i){float v=std::clamp((i-low)/float(high-low),0.f,1.f);v=std::clamp(((v-.5f)*o->contrast+.5f+o->brightness)/o->white_point,0.f,1.f);lut[i]=byte(255*std::pow(v,o->gamma));}
        auto sample=[&](int rx,int ry){rx=std::clamp(rx,0,int(g.rw)-1);ry=std::clamp(ry,0,int(g.rh)-1);uint32_t x=rx,y=ry;
            switch(o->rotation){case 1:x=ry;y=g.h-1-rx;break;case 2:x=g.w-1-rx;y=g.h-1-ry;break;case 3:x=g.w-1-ry;y=rx;break;}return float(src[size_t(g.y+y)*w+g.x+x]);};
        rows(oh,o->threads,[&](uint32_t a,uint32_t b){for(uint32_t y=a;y<b;++y)for(uint32_t x=0;x<ow;++x){
            if(ow==g.rw&&oh==g.rh){dst[size_t(y)*ow+x]=lut[uint8_t(sample(x,y))];continue;}
            float sx=(x+.5f)*g.rw/ow-.5f,sy=(y+.5f)*g.rh/oh-.5f;int ix=int(std::floor(sx)),iy=int(std::floor(sy));float fx=sx-ix,fy=sy-iy;
            float top=sample(ix,iy)*(1-fx)+sample(ix+1,iy)*fx,bot=sample(ix,iy+1)*(1-fx)+sample(ix+1,iy+1)*fx;dst[size_t(y)*ow+x]=lut[byte(top*(1-fy)+bot*fy)];
        }});
        if(o->blur){graySmooth(dst,ow,oh,o->filter_radius,o->blur_method==1,o->threads,ws);rows(oh,o->threads,[&](uint32_t a,uint32_t b){for(size_t i=size_t(a)*ow;i<size_t(b)*ow;++i)dst[i]=byte(dst[i]+(ws.b[i]-float(dst[i]))*o->blur);});}
        if(o->sharpen){if(o->sharpen_method==0)graySmooth(dst,ow,oh,o->filter_radius,false,o->threads,ws);else ws.a.assign(dst,dst+size_t(ow)*oh);
            rows(oh,o->threads,[&](uint32_t a,uint32_t b){for(uint32_t y=a;y<b;++y)for(uint32_t x=0;x<ow;++x){size_t i=size_t(y)*ow+x;float delta;
                if(!o->sharpen_method)delta=dst[i]-float(ws.b[i]);else{auto get=[&](int xx,int yy){return ws.a[size_t(std::clamp(yy,0,int(oh)-1))*ow+std::clamp(xx,0,int(ow)-1)];};delta=(4.f*ws.a[i]-get(int(x)-1,y)-get(int(x)+1,y)-get(x,int(y)-1)-get(x,int(y)+1))*.25f;}
                if(std::abs(delta)>=o->sharpen_threshold)dst[i]=byte(dst[i]+o->sharpen*delta);
            }});
        }
        grayReduce(dst,ow,oh,*o,ws);return 0;
    }catch(...){return -4;}
}
extern "C" int ce_gray_from_rgba(const uint8_t*src,uint32_t w,uint32_t h,uint8_t*dst,size_t n){
    if(!src||!dst||src==dst)return -1;
    if(!w||!h||uint64_t(w)*h>maxPixels)return -2;
    if(n<size_t(w)*h)return -3;
    std::atomic<bool>gray{true};rows(h,0,[&](uint32_t a,uint32_t b){for(size_t i=size_t(a)*w;i<size_t(b)*w;++i){auto p=src+i*4;if(p[0]!=p[1]||p[1]!=p[2])gray=false;dst[i]=p[0];}});return gray?0:-5;
}
extern "C" int ce_gray_to_rgba(const uint8_t*src,uint32_t w,uint32_t h,uint8_t*dst,size_t n){
    if(!src||!dst||src==dst)return -1;
    if(!w||!h||uint64_t(w)*h>maxPixels)return -2;
    if(n<size_t(w)*h*4)return -3;
    rows(h,0,[&](uint32_t a,uint32_t b){for(size_t i=size_t(a)*w;i<size_t(b)*w;++i){auto p=dst+i*4;p[0]=p[1]=p[2]=src[i];p[3]=255;}});return 0;
}
extern "C" int ce_gray_pack(const uint8_t*src,uint32_t w,uint32_t h,int32_t bits,uint8_t*dst,size_t n){
    if(!src||!dst||src==dst||(bits!=1&&bits!=2&&bits!=4&&bits!=8))return -1;
    if(!w||!h||uint64_t(w)*h>maxPixels)return -2;
    size_t stride=(size_t(w)*bits+7)/8;if(n<stride*h)return -3;
    rows(h,0,[&](uint32_t a,uint32_t b){for(uint32_t y=a;y<b;++y){auto out=dst+size_t(y)*stride;std::fill_n(out,stride,0);
        for(uint32_t x=0;x<w;++x){int value=(int(src[size_t(y)*w+x])*((1<<bits)-1)+127)/255;size_t bit=size_t(x)*bits;out[bit/8]|=uint8_t(value<<(8-bits-bit%8));}
    }});return 0;
}
