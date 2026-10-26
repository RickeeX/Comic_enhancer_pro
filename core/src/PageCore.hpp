// C entry points for page geometry and topology-aware binary postprocessing.
namespace {
bool pageSize(uint32_t w,uint32_t h){return w&&h&&w<=50000&&h<=50000&&uint64_t(w)*h<=maxPixels;}
struct InkComponent { uint32_t left,right,top,bottom; std::vector<uint32_t> small; };
template<int C,class F> void components(const uint8_t *rgba,uint32_t w,uint32_t h,int threshold,int diameter,F visit){
    size_t n=size_t(w)*h;std::vector<uint8_t> seen((n+7)/8);std::vector<uint32_t> stack;
    auto marked=[&](size_t i){return (seen[i>>3]>>(i&7))&1;};
    auto push=[&](uint32_t i){seen[i>>3]|=uint8_t(1u<<(i&7));stack.push_back(i);};
    for(uint32_t start=0;start<n;++start){
        if(marked(start)||(C==1?rgba[size_t(start)]:luminance(rgba+size_t(start)*C))>threshold)continue;
        InkComponent c{start%w,start%w,start/w,start/w,{}};bool small=true;push(start);
        while(!stack.empty()){
            uint32_t i=stack.back();stack.pop_back();uint32_t x=i%w,y=i/w;
            c.left=std::min(c.left,x);c.right=std::max(c.right,x);c.top=std::min(c.top,y);c.bottom=std::max(c.bottom,y);
            if(small){
                if(c.right-c.left+1>uint32_t(diameter)||c.bottom-c.top+1>uint32_t(diameter)){small=false;c.small.clear();}
                else c.small.push_back(i);
            }
            for(int dy=-1;dy<=1;++dy)for(int dx=-1;dx<=1;++dx){
                int xx=int(x)+dx,yy=int(y)+dy;if(xx<0||yy<0||xx>=int(w)||yy>=int(h))continue;
                uint32_t next=uint32_t(yy)*w+uint32_t(xx);
                if(!marked(next)&&(C==1?rgba[size_t(next)]:luminance(rgba+size_t(next)*C))<=threshold)push(next);
            }
        }
        visit(c,small);
    }
}
float cubic(float x){x=std::abs(x);return x<1?(1.5f*x-2.5f)*x*x+1:x<2?((-.5f*x+2.5f)*x-4)*x+2:0;}
}
template<int C> int canvas(const uint8_t*src,uint32_t w,uint32_t h,uint32_t ow,uint32_t oh,const float rect[4],int32_t method,uint8_t*dst,size_t capacity){
    if(!src||!dst||src==dst||!rect||method<0||method>2)return -1;
    if(!pageSize(w,h)||!pageSize(ow,oh))return -2;
    for(int i=0;i<4;++i)if(!std::isfinite(rect[i])||std::abs(rect[i])>1.e9f)return -1;
    if(rect[2]<=0||rect[3]<=0)return -1;
    if(capacity<size_t(ow)*oh*C)return -3;
    try{
        struct Sample{int index[4];float weight[4];bool inside;};
        auto make=[&](uint32_t length,uint32_t source,float origin,float extent){
            std::vector<Sample> samples(length);
            for(uint32_t i=0;i<length;++i){auto &s=samples[i];s.inside=i+.5f>=origin&&i+.5f<origin+extent;
                if(!s.inside){s.index[0]=0;s.weight[0]=1;continue;}
                double position=(i+.5-origin)*source/extent-.5;int base=int(std::floor(position));
                if(method==0){s.index[0]=std::clamp(int(std::lround(position)),0,int(source)-1);s.weight[0]=1;}
                else if(method==1){s.index[0]=std::clamp(base,0,int(source)-1);s.index[1]=std::clamp(base+1,0,int(source)-1);s.weight[1]=float(position-base);s.weight[0]=1-s.weight[1];}
                else for(int j=0;j<4;++j){s.index[j]=std::clamp(base+j-1,0,int(source)-1);s.weight[j]=cubic(float(position-(base+j-1)));}
            }return samples;
        };
        auto xs=make(ow,w,rect[0],rect[2]),ys=make(oh,h,rect[1],rect[3]);int taps=method==0?1:method==1?2:4;
        rows(oh,0,[&](uint32_t a,uint32_t b){
            // Only a few horizontally filtered rows are needed at a time.
            // Reuse them on enlargement: 4+4 taps instead of a 4x4 kernel.
            std::array<std::vector<float>,4> cache;
            std::array<int,4> keys{{-1,-1,-1,-1}};
            if(method)for(int i=0;i<taps;++i)cache[i].resize(size_t(ow)*(C==1?1:3));
            for(uint32_t y=a;y<b;++y){
                const auto &sy=ys[y];auto line=dst+size_t(y)*ow*C;
                if(!sy.inside){std::fill_n(line,size_t(ow)*C,255);continue;}
                std::array<const float*,4> filtered{};
                if(method)for(int yy=0;yy<taps;++yy){
                    int iy=sy.index[yy],slot=iy%taps;
                    if(keys[slot]!=iy){
                        auto in=src+size_t(iy)*w*C;auto &target=cache[slot];
                        for(uint32_t x=0;x<ow;++x){const auto &sx=xs[x];if(!sx.inside)continue;
                            for(int c=0;c<(C==1?1:3);++c){float value=0;
                                for(int xx=0;xx<taps;++xx)value+=in[size_t(sx.index[xx])*C+c]*sx.weight[xx];
                                target[size_t(x)*(C==1?1:3)+c]=value;}
                        }keys[slot]=iy;
                    }filtered[yy]=cache[slot].data();
                }
                for(uint32_t x=0;x<ow;++x){auto p=line+size_t(x)*C;const auto &sx=xs[x];
                    if(!sx.inside){std::fill_n(p,C,255);continue;}
                    if(!method){auto in=src+(size_t(sy.index[0])*w+sx.index[0])*C;std::copy_n(in,C==1?1:3,p);}
                    else for(int c=0;c<(C==1?1:3);++c){float value=0;
                        for(int yy=0;yy<taps;++yy)value+=filtered[yy][size_t(x)*(C==1?1:3)+c]*sy.weight[yy];
                        p[c]=byte(value);}
                    if constexpr(C==4)p[3]=255;
                }
            }
        });return 0;
    }catch(...){return -4;}
}
template<int C> int despeckle(uint8_t*rgba,uint32_t w,uint32_t h,int32_t diameter,int32_t threshold,int32_t removeEdges){
    if(!rgba||diameter<0||diameter>128||threshold<0||threshold>254||removeEdges<0||removeEdges>1)return -1;
    if(!pageSize(w,h))return -2;
    try{
        if(removeEdges){
            std::vector<uint32_t> queue;
            auto push=[&](uint32_t i){auto p=rgba+size_t(i)*C;if((C==1?p[0]:luminance(p))<=threshold){std::fill_n(p,C==1?1:3,255);queue.push_back(i);}};
            for(uint32_t x=0;x<w;++x){push(x);push((h-1)*w+x);}for(uint32_t y=0;y<h;++y){push(y*w);push(y*w+w-1);}
            while(!queue.empty()){auto i=queue.back();queue.pop_back();int x=i%w,y=i/w;
                for(int dy=-1;dy<=1;++dy)for(int dx=-1;dx<=1;++dx){int xx=x+dx,yy=y+dy;if(xx>=0&&yy>=0&&xx<int(w)&&yy<int(h))push(uint32_t(yy)*w+xx);}
            }
        }
        if(diameter)components<C>(rgba,w,h,threshold,diameter,[&](const InkComponent &c,bool small){
            if(small)for(auto i:c.small){auto p=rgba+size_t(i)*C;std::fill_n(p,C==1?1:3,255);}
        });return 0;
    }catch(...){return -4;}
}
template<int C> int contentBounds(const uint8_t*rgba,uint32_t w,uint32_t h,int32_t threshold,int32_t diameter,uint32_t out[4]){
    if(!rgba||!out||threshold<0||threshold>254||diameter<0||diameter>128)return -1;
    if(!pageSize(w,h))return -2;
    try{
        uint32_t left=w,top=h,right=0,bottom=0;bool found=false;
        if(!diameter){
            // No component rejection requested: a parallel scan is sufficient.
            std::mutex merge;
            rows(h,0,[&](uint32_t a,uint32_t b){uint32_t l=w,t=h,r=0,bt=0;bool any=false;
                for(uint32_t y=a;y<b;++y)for(uint32_t x=0;x<w;++x)if((C==1?rgba[size_t(y)*w+x]:luminance(rgba+(size_t(y)*w+x)*C))<=threshold){
                    l=std::min(l,x);r=std::max(r,x);t=std::min(t,y);bt=y;any=true;}
                if(any){std::lock_guard<std::mutex> guard(merge);found=true;left=std::min(left,l);right=std::max(right,r);top=std::min(top,t);bottom=std::max(bottom,bt);}
            });
        }else components<C>(rgba,w,h,threshold,diameter,[&](const InkComponent &c,bool small){if(small)return;found=true;left=std::min(left,c.left);top=std::min(top,c.top);right=std::max(right,c.right);bottom=std::max(bottom,c.bottom);});
        out[0]=found?left:0;out[1]=found?top:0;out[2]=found?right-left+1:w;out[3]=found?bottom-top+1:h;return 0;
    }catch(...){return -4;}
}
template<int C> int smoothBinary(uint8_t*rgba,uint32_t w,uint32_t h,int32_t passes,int32_t fill){
    if(!rgba||passes<1||passes>3||fill<0||fill>1)return -1;
    if(!pageSize(w,h))return -2;
    try{
        for(size_t i=0;i<size_t(w)*h;++i){auto p=rgba+i*C;if((p[0]!=0&&p[0]!=255)||(C==4&&(p[1]!=p[0]||p[2]!=p[0])))return -1;}
        std::vector<uint8_t> original(size_t(w)*h);
        for(int pass=0;pass<passes;++pass){
            for(size_t i=0;i<original.size();++i)original[i]=rgba[i*C];
            rows(h,0,[&](uint32_t a,uint32_t b){for(uint32_t y=a;y<b;++y)for(uint32_t x=0;x<w;++x){
                if(!x||!y||x+1==w||y+1==h)continue;
                int center=original[size_t(y)*w+x]==0;if(!center&&!fill)continue;
                // Every template has at least one unlike north/south neighbor.
                if(original[size_t(y-1)*w+x]==original[size_t(y)*w+x]&&original[size_t(y+1)*w+x]==original[size_t(y)*w+x])continue;
                // Same four hit/miss templates encoded as neighborhood masks.
                auto row=original.data()+size_t(y)*w+x;
                unsigned mask=(row[-int(w)-1]==0)|((row[-int(w)]==0)<<1)|((row[-int(w)+1]==0)<<2)|
                    ((row[-1]==0)<<3)|((row[1]==0)<<4)|((row[w-1]==0)<<5)|((row[w]==0)<<6)|((row[w+1]==0)<<7);
                if(!center)mask^=255;
                if(mask==0xe0||mask==0x07||mask==0x29||mask==0x94){auto p=rgba+(size_t(y)*w+x)*C;std::fill_n(p,C==1?1:3,center?255:0);}
            }});
        }return 0;
    }catch(...){return -4;}
}
template<int C> int invert(uint8_t*rgba,uint32_t w,uint32_t h){
    if(!rgba)return -1;
    if(!pageSize(w,h))return -2;
    try{rows(h,0,[&](uint32_t a,uint32_t b){for(size_t i=size_t(a)*w*C;i<size_t(b)*w*C;++i)if(i%C!=(C==1?1:3))rgba[i]=255-rgba[i];});return 0;}catch(...){return -4;}
}

template<int C> int mirror(const uint8_t*src,uint32_t w,uint32_t h,int32_t horizontal,int32_t vertical,uint8_t*dst,size_t capacity){
    if(!src||!dst||src==dst||horizontal<0||horizontal>1||vertical<0||vertical>1)return -1;
    if(!pageSize(w,h))return -2;
    if(capacity<size_t(w)*h*C)return -3;
    try{rows(h,0,[&](uint32_t a,uint32_t b){for(uint32_t y=a;y<b;++y){uint32_t yy=vertical?h-1-y:y;
        if(!horizontal){std::copy_n(src+size_t(yy)*w*C,size_t(w)*C,dst+size_t(y)*w*C);continue;}
        for(uint32_t x=0;x<w;++x)std::copy_n(src+(size_t(yy)*w+w-1-x)*C,C,dst+(size_t(y)*w+x)*C);
    }});return 0;}catch(...){return -4;}
}

template<int C> int whitenOutside(uint8_t*rgba,uint32_t w,uint32_t h,const float rect[4]){
    if(!rgba||!rect)return -1;
    if(!pageSize(w,h))return -2;
    for(int i=0;i<4;++i)if(!std::isfinite(rect[i])||std::abs(rect[i])>1.e9f)return -1;
    if(rect[2]<0||rect[3]<0)return -1;
    try{rows(h,0,[&](uint32_t a,uint32_t b){for(uint32_t y=a;y<b;++y)for(uint32_t x=0;x<w;++x)
        if(x+.5f<rect[0]||x+.5f>=rect[0]+rect[2]||y+.5f<rect[1]||y+.5f>=rect[1]+rect[3]){
            auto p=rgba+(size_t(y)*w+x)*C;std::fill_n(p,C==1?1:3,255);
        }
    });return 0;}catch(...){return -4;}
}

template<int C> int blit(const uint8_t*src,uint32_t w,uint32_t h,uint8_t*dst,uint32_t dw,uint32_t dh,uint32_t x,uint32_t y,size_t capacity){
    if(!src||!dst||src==dst)return -1;
    if(!pageSize(w,h)||!pageSize(dw,dh)||uint64_t(x)+w>dw||uint64_t(y)+h>dh)return -2;
    if(capacity<size_t(dw)*dh*C)return -3;
    try{rows(h,0,[&](uint32_t a,uint32_t b){for(uint32_t row=a;row<b;++row)std::copy_n(src+size_t(row)*w*C,size_t(w)*C,dst+(size_t(row+y)*dw+x)*C);});return 0;}catch(...){return -4;}
}

#define CE_PAGE_WRAPPERS(SUFFIX,CHANNELS) \
extern "C" int ce_canvas##SUFFIX(const uint8_t*s,uint32_t w,uint32_t h,uint32_t ow,uint32_t oh,const float*r,int32_t m,uint8_t*d,size_t n){return canvas<CHANNELS>(s,w,h,ow,oh,r,m,d,n);} \
extern "C" int ce_despeckle##SUFFIX(uint8_t*p,uint32_t w,uint32_t h,int32_t d,int32_t t,int32_t e){return despeckle<CHANNELS>(p,w,h,d,t,e);} \
extern "C" int ce_content_bounds##SUFFIX(const uint8_t*p,uint32_t w,uint32_t h,int32_t t,int32_t d,uint32_t*r){return contentBounds<CHANNELS>(p,w,h,t,d,r);} \
extern "C" int ce_smooth_binary##SUFFIX(uint8_t*p,uint32_t w,uint32_t h,int32_t n,int32_t f){return smoothBinary<CHANNELS>(p,w,h,n,f);} \
extern "C" int ce_invert##SUFFIX(uint8_t*p,uint32_t w,uint32_t h){return invert<CHANNELS>(p,w,h);} \
extern "C" int ce_mirror##SUFFIX(const uint8_t*s,uint32_t w,uint32_t h,int32_t x,int32_t y,uint8_t*d,size_t n){return mirror<CHANNELS>(s,w,h,x,y,d,n);} \
extern "C" int ce_whiten_outside##SUFFIX(uint8_t*p,uint32_t w,uint32_t h,const float*r){return whitenOutside<CHANNELS>(p,w,h,r);} \
extern "C" int ce_blit##SUFFIX(const uint8_t*s,uint32_t w,uint32_t h,uint8_t*d,uint32_t dw,uint32_t dh,uint32_t x,uint32_t y,size_t n){return blit<CHANNELS>(s,w,h,d,dw,dh,x,y,n);}
CE_PAGE_WRAPPERS(,4)
CE_PAGE_WRAPPERS(_gray,1)
#undef CE_PAGE_WRAPPERS
