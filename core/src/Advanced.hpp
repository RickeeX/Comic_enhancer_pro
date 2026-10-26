// Internal C++17 algorithms. Included inside ComicCore's anonymous namespace.
uint8_t luminance(const uint8_t *p){return (54*p[0]+183*p[1]+19*p[2]+128)>>8;}
int otsu(const std::array<uint64_t,256>&hist){
    double total=0,moment=0;for(int i=0;i<256;++i){total+=hist[i];moment+=i*double(hist[i]);}
    double n=0,s=0,best=-1;int threshold=0,occupied=0,last=0;
    for(int i=0;i<256;++i)if(hist[i]){++occupied;last=i;}
    if(occupied<=1)return std::max(0,last-1);
    for(int i=0;i<255;++i){
        n+=hist[i];s+=i*double(hist[i]);if(n==0||n==total)continue;
        double delta=s/n-(moment-s)/(total-n),score=n*(total-n)*delta*delta;
        if(score>best){best=score;threshold=i;}
    }
    return threshold;
}
float estimate(const uint8_t*src,uint32_t w,uint32_t h,bool vertical,float limit){
    // Bounded 800px analysis and at most 60k ink points, independent of source size.
    uint32_t step=std::max(1u,(std::max(w,h)+799)/800);
    uint32_t sw=(w+step-1)/step,sh=(h+step-1)/step;
    std::array<uint64_t,256> hist{};
    std::vector<uint8_t> gray(size_t(sw)*sh);
    for(uint32_t y=0;y<sh;++y)for(uint32_t x=0;x<sw;++x){
        auto v=luminance(src+(size_t(std::min(y*step,h-1))*w+std::min(x*step,w-1))*4);
        gray[size_t(y)*sw+x]=v;++hist[v];
    }
    int threshold=std::min(otsu(hist),200);
    struct Point{float x,y;};std::vector<Point> points;
    for(uint32_t y=sh/20;y<sh-sh/20;++y)for(uint32_t x=sw/20;x<sw-sw/20;++x)
        if(gray[size_t(y)*sw+x]<=threshold)points.push_back({x-sw*.5f,y-sh*.5f});
    if(points.size()<100||points.size()>gray.size()*.5)return 0;
    size_t stride=std::max(size_t(1),(points.size()+59999)/60000);
    const int bins=int(sw+sh)*2+8,offset=bins/2;
    auto score=[&](float degrees){
        double rad=degrees*3.141592653589793/180,c=std::cos(rad),s=std::sin(rad);
        std::vector<uint32_t> profile(bins);
        for(size_t i=0;i<points.size();i+=stride){auto p=points[i];
            int bin=int(std::lround(vertical?c*p.x-s*p.y:s*p.x+c*p.y))+offset;
            if(bin>=0&&bin<bins)++profile[bin];
        }
        double sum=0;for(auto n:profile)sum+=double(n)*n;return sum;
    };
    float bestAngle=0;double baseline=score(0),best=baseline;
    int count=int(std::ceil(limit*4));
    for(int i=-count;i<=count;++i){float a=i*.25f;if(std::abs(a)>limit)continue;
        double s=score(a);if(s>best){best=s;bestAngle=a;}}
    float center=bestAngle;
    for(int i=-4;i<=4;++i){float a=center+i*.05f;if(std::abs(a)>limit)continue;
        double s=score(a);if(s>best){best=s;bestAngle=a;}}
    return best>baseline*1.025?bestAngle:0;
}
void rotateFine(uint8_t*dst,uint32_t w,uint32_t h,float degrees,int threads){
    std::vector<uint8_t> src(dst,dst+size_t(w)*h*4);
    double a=degrees*3.141592653589793/180,c=std::cos(a),s=std::sin(a),cx=(w-1)*.5,cy=(h-1)*.5;
    rows(h,threads,[&](uint32_t begin,uint32_t end){
        for(uint32_t y=begin;y<end;++y)for(uint32_t x=0;x<w;++x){
            double xx=c*(x-cx)+s*(y-cy)+cx,yy=-s*(x-cx)+c*(y-cy)+cy;
            int ix=int(std::floor(xx)),iy=int(std::floor(yy));float fx=xx-ix,fy=yy-iy;
            for(int ch=0;ch<3;++ch){
                auto sample=[&](int px,int py){return px<0||py<0||px>=int(w)||py>=int(h)?255.f:float(src[(size_t(py)*w+px)*4+ch]);};
                dst[(size_t(y)*w+x)*4+ch]=byte((sample(ix,iy)*(1-fx)+sample(ix+1,iy)*fx)*(1-fy)+(sample(ix,iy+1)*(1-fx)+sample(ix+1,iy+1)*fx)*fy);
            }
        }
    });
}
std::vector<uint8_t> smooth(const uint8_t*src,uint32_t w,uint32_t h,int method,int r,float sigma,int threads){
    std::vector<uint8_t> out(size_t(w)*h*4,255);
    if(method<=1){
        // Separable binomial Gaussian / box: O(radius * pixels), no square kernel.
        std::vector<uint8_t> tmp(out.size(),255);std::array<float,7> weights{};float sum=0;
        for(int i=0;i<=2*r;++i){float k=1;if(method==0)for(int j=1;j<=i;++j)k*=float(2*r-j+1)/j;weights[i]=k;sum+=k;}
        for(auto &v:weights)v/=sum;
        for(int pass=0;pass<2;++pass){const uint8_t *in=pass?tmp.data():src;auto &target=pass?out:tmp;
            rows(h,threads,[&](uint32_t a,uint32_t b){for(uint32_t y=a;y<b;++y)for(uint32_t x=0;x<w;++x)for(int ch=0;ch<3;++ch){
                float v=0;for(int d=-r;d<=r;++d){int xx=pass?int(x):std::clamp(int(x)+d,0,int(w)-1),yy=pass?std::clamp(int(y)+d,0,int(h)-1):int(y);
                    v+=in[(size_t(yy)*w+xx)*4+ch]*weights[d+r];}
                target[(size_t(y)*w+x)*4+ch]=byte(v);
            }});
        }
    }else{
        std::array<float,256> range{};std::array<float,49> spatial{};
        for(int i=0;i<256;++i)range[i]=std::exp(-float(i*i)/(2*sigma*sigma));
        for(int dy=-r;dy<=r;++dy)for(int dx=-r;dx<=r;++dx)spatial[(dy+r)*(2*r+1)+dx+r]=std::exp(-float(dx*dx+dy*dy)/(2*r*r));
        rows(h,threads,[&](uint32_t a,uint32_t b){for(uint32_t y=a;y<b;++y)for(uint32_t x=0;x<w;++x){
            std::array<std::array<uint8_t,49>,3> values{};std::array<float,3> sum{};float weight=0;int n=0;
            auto center=src+(size_t(y)*w+x)*4;
            for(int dy=-r;dy<=r;++dy)for(int dx=-r;dx<=r;++dx){
                auto p=src+(size_t(std::clamp(int(y)+dy,0,int(h)-1))*w+std::clamp(int(x)+dx,0,int(w)-1))*4;
                float k=method==3?spatial[n]*range[std::abs(int(luminance(p))-luminance(center))]:1;
                for(int ch=0;ch<3;++ch){if(method==2)values[ch][n]=p[ch];else sum[ch]+=k*p[ch];}
                weight+=k;++n;
            }
            for(int ch=0;ch<3;++ch){
                if(method==2){std::nth_element(values[ch].begin(),values[ch].begin()+n/2,values[ch].begin()+n);out[(size_t(y)*w+x)*4+ch]=values[ch][n/2];}
                else out[(size_t(y)*w+x)*4+ch]=byte(sum[ch]/weight);
            }
        }});
    }
    return out;
}
void filter(uint8_t*dst,uint32_t w,uint32_t h,const CEOptions&o){
    size_t size=size_t(w)*h*4;
    if(o.blur>0){auto soft=smooth(dst,w,h,o.blur_method,o.filter_radius,o.edge_sigma,o.threads);
        rows(h,o.threads,[&](uint32_t a,uint32_t b){for(size_t i=size_t(a)*w*4;i<size_t(b)*w*4;++i)if(i%4!=3)dst[i]=byte(dst[i]+(soft[i]-float(dst[i]))*o.blur);});}
    if(o.sharpen<=0)return;
    std::vector<uint8_t> base(dst,dst+size),soft;
    if(o.sharpen_method==0)soft=smooth(base.data(),w,h,0,o.filter_radius,o.edge_sigma,o.threads);
    rows(h,o.threads,[&](uint32_t a,uint32_t b){for(uint32_t y=a;y<b;++y)for(uint32_t x=0;x<w;++x)for(int ch=0;ch<3;++ch){
        size_t i=(size_t(y)*w+x)*4+ch;float delta;
        if(o.sharpen_method==0)delta=base[i]-float(soft[i]);
        else{auto get=[&](int xx,int yy){return base[(size_t(std::clamp(yy,0,int(h)-1))*w+std::clamp(xx,0,int(w)-1))*4+ch];};
            delta=(4.f*base[i]-get(int(x)-1,y)-get(int(x)+1,y)-get(x,int(y)-1)-get(x,int(y)+1))*.25f;}
        if(std::abs(delta)>=o.sharpen_threshold)dst[i]=byte(base[i]+o.sharpen*delta);
    }});
}
void morphology(std::vector<uint8_t>&gray,uint32_t w,uint32_t h,bool expandBlack,int threads){
    auto src=gray;
    rows(h,threads,[&](uint32_t a,uint32_t b){for(uint32_t y=a;y<b;++y)for(uint32_t x=0;x<w;++x){
        uint8_t result=expandBlack?255:0;
        for(int dy=-1;dy<=1;++dy)for(int dx=-1;dx<=1;++dx){
            int xx=int(x)+dx,yy=int(y)+dy;
            uint8_t v=xx<0||yy<0||xx>=int(w)||yy>=int(h)?255:src[size_t(yy)*w+xx];
            result=expandBlack?std::min(result,v):std::max(result,v);
        }
        gray[size_t(y)*w+x]=result;
    }});
}
void reduce(uint8_t*dst,uint32_t w,uint32_t h,const CEOptions&o){
    if(!o.binarization&&!o.levels)return;
    std::vector<uint8_t> gray(size_t(w)*h);
    for(size_t i=0;i<gray.size();++i)gray[i]=luminance(dst+i*4);
    if(o.binarization){
        int threshold=int(o.threshold);
        if(o.binarization==2){std::array<uint64_t,256> hist{};for(auto v:gray)++hist[v];threshold=otsu(hist);}
        if(o.binarization==3){
            auto input=gray;int radius=o.adaptive_radius;
            rows(h,o.threads,[&](uint32_t begin,uint32_t end){
                std::vector<uint64_t> col(w),squared(w);
                auto add=[&](int y,bool remove){if(y<0||y>=int(h))return;
                    for(uint32_t x=0;x<w;++x){uint64_t v=input[size_t(y)*w+x];if(remove){col[x]-=v;squared[x]-=v*v;}else{col[x]+=v;squared[x]+=v*v;}}};
                for(int y=std::max(0,int(begin)-radius);y<=std::min(int(h)-1,int(begin)+radius);++y)add(y,false);
                for(uint32_t y=begin;y<end;++y){
                    if(y>begin){add(int(y)-radius-1,true);add(int(y)+radius,false);}
                    uint64_t sum=0,sq=0;for(int x=0;x<=std::min(int(w)-1,radius);++x){sum+=col[x];sq+=squared[x];}
                    int ny=std::min(int(h)-1,int(y)+radius)-std::max(0,int(y)-radius)+1;
                    for(uint32_t x=0;x<w;++x){
                        if(x){int left=int(x)-radius-1,right=int(x)+radius;if(left>=0){sum-=col[left];sq-=squared[left];}if(right<int(w)){sum+=col[right];sq+=squared[right];}}
                        int nx=std::min(int(w)-1,int(x)+radius)-std::max(0,int(x)-radius)+1;
                        double n=double(nx)*ny,mean=sum/n,dev=std::sqrt(std::max(0.,sq/n-mean*mean));
                        double t=mean*(1+o.sauvola_k*(dev/128-1));gray[size_t(y)*w+x]=input[size_t(y)*w+x]<=t?0:255;
                    }
                }
            });
        }else for(auto &v:gray)v=v<=threshold?0:255;
        for(int pass=0;pass<o.cleanup_passes&&o.cleanup;++pass){
            if(o.cleanup>=3){morphology(gray,w,h,o.cleanup==4,o.threads);morphology(gray,w,h,o.cleanup==3,o.threads);}
            else{auto input=gray;
                rows(h,o.threads,[&](uint32_t a,uint32_t b){for(uint32_t y=a;y<b;++y)for(uint32_t x=0;x<w;++x){
                    int black=0;for(int dy=-1;dy<=1;++dy)for(int dx=-1;dx<=1;++dx){int xx=int(x)+dx,yy=int(y)+dy;
                        if(xx>=0&&yy>=0&&xx<int(w)&&yy<int(h)&&input[size_t(yy)*w+xx]==0)++black;}
                    auto &v=gray[size_t(y)*w+x];if(o.cleanup==2)v=black>=5?0:255;else if(v==0&&black<=1)v=255;
                }});
            }
        }
    }else{
        int levels=o.levels;
        auto quant=[&](float v){return byte(std::round(std::clamp(v,0.f,255.f)*(levels-1)/255.f)*255.f/(levels-1));};
        if(o.dither==2){
            std::vector<float> current(w+2),next(w+2);
            for(uint32_t y=0;y<h;++y){int dir=y%2?-1:1;
                for(uint32_t j=0;j<w;++j){int x=dir==1?int(j):int(w-1-j);float v=std::clamp(gray[size_t(y)*w+x]+current[x+1],0.f,255.f);
                    auto q=quant(v);gray[size_t(y)*w+x]=q;float e=v-q;
                    current[x+1+dir]+=e*7/16;next[x+1-dir]+=e*3/16;next[x+1]+=e*5/16;next[x+1+dir]+=e/16;}
                current.swap(next);std::fill(next.begin(),next.end(),0);
            }
        }else{
            constexpr int bayer[16]={0,8,2,10,12,4,14,6,3,11,1,9,15,7,13,5};
            rows(h,o.threads,[&](uint32_t a,uint32_t b){for(uint32_t y=a;y<b;++y)for(uint32_t x=0;x<w;++x){size_t i=size_t(y)*w+x;
                float offset=o.dither==1?((bayer[(y%4)*4+x%4]+.5f)/16-.5f)*255/(levels-1):0;gray[i]=quant(gray[i]+offset);}});
        }
    }
    rows(h,o.threads,[&](uint32_t a,uint32_t b){for(size_t i=size_t(a)*w;i<size_t(b)*w;++i)dst[i*4]=dst[i*4+1]=dst[i*4+2]=gray[i];});
}
