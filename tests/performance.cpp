#include "ComicCore.h"
#include <chrono>
#include <cstdlib>
#include <iostream>
#include <vector>

// Repeatable end-to-end C API timings, including output/scratch allocation.
// No file codecs or GUI. Pass a smaller width/height for quick local checks.
int main(int argc,char**argv){
    const uint32_t w=argc>1?uint32_t(std::stoul(argv[1])):5000;
    const uint32_t h=argc>2?uint32_t(std::stoul(argv[2])):6000;
    if(!w||!h||uint64_t(w)*h>100000000)return 1;
    std::vector<uint8_t> source(size_t(w)*h*4,255);
    for(uint32_t y=0;y<h;++y)for(uint32_t x=0;x<w;++x){
        auto p=source.data()+(size_t(y)*w+x)*4;
        uint8_t v=uint8_t((x%19<3&&y%31<13?35:180)+(x*17+y*31)%35);
        p[0]=v;p[1]=uint8_t(v+4);p[2]=uint8_t(v+8);
    }
    auto measure=[&](const char*name,auto operation){
        auto begin=std::chrono::steady_clock::now();int status=operation();
        if(status){std::cerr<<name<<" failed: "<<status<<'\n';std::exit(1);}
        std::cout<<name<<": "<<std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-begin).count()<<" ms"<<std::endl;
    };
    std::cout<<w<<'x'<<h<<" ("<<double(w)*h/1e6<<" MP), automatic threads\n";
    for(int mode=0;mode<9;++mode){
        auto o=ce_defaults();
        if(mode==1){o.auto_levels=1;o.contrast=1.1f;}
        if(mode>=2&&mode<=5){o.blur=1;o.blur_method=mode-2;o.filter_radius=3;}
        if(mode==6){o.sharpen=.4f;o.filter_radius=3;}
        if(mode>=7)o.binarization=mode==7?2:3;
        measure(std::vector<const char*>{"Identity","Tone","Gaussian r3","Box r3","Median r3","Bilateral r3","Unsharp r3","Otsu","Sauvola"}[mode],[&]{
            std::vector<uint8_t> output(source.size());
            return ce_process(source.data(),w,h,&o,output.data(),output.size());
        });
    }
    measure("Bicubic 4/3",[&]{uint32_t ow=w*4/3,oh=h*4/3;std::vector<uint8_t> out(size_t(ow)*oh*4);float r[]={0,0,float(ow),float(oh)};
        return ce_canvas(source.data(),w,h,ow,oh,r,2,out.data(),out.size());});
    measure("Content bounds",[&]{uint32_t out[4];return ce_content_bounds(source.data(),w,h,127,0,out);});
    auto o=ce_defaults();o.binarization=1;std::vector<uint8_t> binary(source.size());
    if(ce_process(source.data(),w,h,&o,binary.data(),binary.size()))return 1;
    measure("Smooth binary",[&]{return ce_smooth_binary(binary.data(),w,h,1,1);});
}
