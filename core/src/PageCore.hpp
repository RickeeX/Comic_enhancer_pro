// C entry points for page geometry and topology-aware binary postprocessing.
namespace {
bool pageSize(uint32_t w,uint32_t h){return w&&h&&w<=50000&&h<=50000&&uint64_t(w)*h<=maxPixels;}
struct Component { uint32_t left,right,top,bottom; std::vector<uint32_t> small; };
template<class F> void components(const uint8_t *rgba,uint32_t w,uint32_t h,int threshold,int diameter,F visit){
    size_t n=size_t(w)*h;std::vector<uint8_t> seen((n+7)/8);std::vector<uint32_t> stack;
    auto marked=[&](size_t i){return (seen[i>>3]>>(i&7))&1;};
    auto push=[&](uint32_t i){seen[i>>3]|=uint8_t(1u<<(i&7));stack.push_back(i);};
    for(uint32_t start=0;start<n;++start){
        if(marked(start)||luminance(rgba+size_t(start)*4)>threshold)continue;
        Component c{start%w,start%w,start/w,start/w,{}};bool small=true;push(start);
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
                if(!marked(next)&&luminance(rgba+size_t(next)*4)<=threshold)push(next);
            }
        }
        visit(c,small);
    }
}
float cubic(float x){x=std::abs(x);return x<1?(1.5f*x-2.5f)*x*x+1:x<2?((-.5f*x+2.5f)*x-4)*x+2:0;}
}
extern "C" int ce_canvas(const uint8_t*src,uint32_t w,uint32_t h,uint32_t ow,uint32_t oh,const float rect[4],int32_t method,uint8_t*dst,size_t capacity){
    if(!src||!dst||src==dst||!rect||method<0||method>2)return -1;
    if(!pageSize(w,h)||!pageSize(ow,oh))return -2;
    for(int i=0;i<4;++i)if(!std::isfinite(rect[i])||std::abs(rect[i])>1.e9f)return -1;
    if(rect[2]<=0||rect[3]<=0)return -1;
    if(capacity<size_t(ow)*oh*4)return -3;
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
        rows(oh,0,[&](uint32_t a,uint32_t b){for(uint32_t y=a;y<b;++y)for(uint32_t x=0;x<ow;++x){
            auto p=dst+(size_t(y)*ow+x)*4;auto sx=xs[x],sy=ys[y];
            if(!sx.inside||!sy.inside){p[0]=p[1]=p[2]=p[3]=255;continue;}
            for(int c=0;c<3;++c){float value=0;
                for(int yy=0;yy<taps;++yy)for(int xx=0;xx<taps;++xx)value+=src[(size_t(sy.index[yy])*w+sx.index[xx])*4+c]*sx.weight[xx]*sy.weight[yy];
                p[c]=byte(value);
            }p[3]=255;
        }});return 0;
    }catch(...){return -4;}
}
extern "C" int ce_despeckle(uint8_t*rgba,uint32_t w,uint32_t h,int32_t diameter,int32_t threshold,int32_t removeEdges){
    if(!rgba||diameter<0||diameter>128||threshold<0||threshold>254||removeEdges<0||removeEdges>1)return -1;
    if(!pageSize(w,h))return -2;
    try{
        if(removeEdges){
            std::vector<uint32_t> queue;
            auto push=[&](uint32_t i){auto p=rgba+size_t(i)*4;if(luminance(p)<=threshold){p[0]=p[1]=p[2]=255;queue.push_back(i);}};
            for(uint32_t x=0;x<w;++x){push(x);push((h-1)*w+x);}for(uint32_t y=0;y<h;++y){push(y*w);push(y*w+w-1);}
            while(!queue.empty()){auto i=queue.back();queue.pop_back();int x=i%w,y=i/w;
                for(int dy=-1;dy<=1;++dy)for(int dx=-1;dx<=1;++dx){int xx=x+dx,yy=y+dy;if(xx>=0&&yy>=0&&xx<int(w)&&yy<int(h))push(uint32_t(yy)*w+xx);}
            }
        }
        if(diameter)components(rgba,w,h,threshold,diameter,[&](const Component &c,bool small){
            if(small)for(auto i:c.small){auto p=rgba+size_t(i)*4;p[0]=p[1]=p[2]=255;}
        });return 0;
    }catch(...){return -4;}
}
extern "C" int ce_content_bounds(const uint8_t*rgba,uint32_t w,uint32_t h,int32_t threshold,int32_t diameter,uint32_t out[4]){
    if(!rgba||!out||threshold<0||threshold>254||diameter<0||diameter>128)return -1;
    if(!pageSize(w,h))return -2;
    try{
        uint32_t left=w,top=h,right=0,bottom=0;bool found=false;
        components(rgba,w,h,threshold,diameter,[&](const Component &c,bool small){if(small)return;found=true;left=std::min(left,c.left);top=std::min(top,c.top);right=std::max(right,c.right);bottom=std::max(bottom,c.bottom);});
        out[0]=found?left:0;out[1]=found?top:0;out[2]=found?right-left+1:w;out[3]=found?bottom-top+1:h;return 0;
    }catch(...){return -4;}
}
extern "C" int ce_smooth_binary(uint8_t*rgba,uint32_t w,uint32_t h,int32_t passes,int32_t fill){
    if(!rgba||passes<1||passes>3||fill<0||fill>1)return -1;
    if(!pageSize(w,h))return -2;
    try{
        for(size_t i=0;i<size_t(w)*h;++i){auto p=rgba+i*4;if((p[0]!=0&&p[0]!=255)||p[1]!=p[0]||p[2]!=p[0])return -1;}
        std::vector<uint8_t> original(size_t(w)*h);
        for(int pass=0;pass<passes;++pass){
            for(size_t i=0;i<original.size();++i)original[i]=rgba[i*4];
            rows(h,0,[&](uint32_t a,uint32_t b){for(uint32_t y=a;y<b;++y)for(uint32_t x=0;x<w;++x){
                if(!x||!y||x+1==w||y+1==h)continue;
                int center=original[size_t(y)*w+x]==0;if(!center&&!fill)continue;
                // An isolated one-pixel protrusion with a solid 3-pixel base.
                // Four rotations; inverse templates fill only open concavities.
                for(int turn=0;turn<4;++turn){
                    bool match=true;
                    for(int dy=-1;dy<=1&&match;++dy)for(int dx=-1;dx<=1;++dx){
                        if(!dx&&!dy)continue;
                        int xx=dx,yy=dy;for(int r=0;r<turn;++r){int old=xx;xx=-yy;yy=old;}
                        bool value=original[size_t(int(y)+yy)*w+int(x)+xx]==0;
                        bool expected=dy==1; if(!center)expected=!expected;
                        if(value!=expected){match=false;break;}
                    }
                    if(match){auto p=rgba+(size_t(y)*w+x)*4;p[0]=p[1]=p[2]=center?255:0;break;}
                }
            }});
        }return 0;
    }catch(...){return -4;}
}
extern "C" int ce_invert(uint8_t*rgba,uint32_t w,uint32_t h){
    if(!rgba)return -1;
    if(!pageSize(w,h))return -2;
    try{rows(h,0,[&](uint32_t a,uint32_t b){for(size_t i=size_t(a)*w*4;i<size_t(b)*w*4;++i)if(i%4!=3)rgba[i]=255-rgba[i];});return 0;}catch(...){return -4;}
}

extern "C" int ce_mirror(const uint8_t*src,uint32_t w,uint32_t h,int32_t horizontal,int32_t vertical,uint8_t*dst,size_t capacity){
    if(!src||!dst||src==dst||horizontal<0||horizontal>1||vertical<0||vertical>1)return -1;
    if(!pageSize(w,h))return -2;
    if(capacity<size_t(w)*h*4)return -3;
    try{rows(h,0,[&](uint32_t a,uint32_t b){for(uint32_t y=a;y<b;++y){uint32_t yy=vertical?h-1-y:y;
        if(!horizontal){std::copy_n(src+size_t(yy)*w*4,size_t(w)*4,dst+size_t(y)*w*4);continue;}
        for(uint32_t x=0;x<w;++x)std::copy_n(src+(size_t(yy)*w+w-1-x)*4,4,dst+(size_t(y)*w+x)*4);
    }});return 0;}catch(...){return -4;}
}
