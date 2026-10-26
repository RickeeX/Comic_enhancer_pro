#include "ComicCore.h"
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <random>
#include <vector>
static int checks=0;
void check(bool ok,const char*message){++checks;if(!ok){std::cerr<<"FAIL: "<<message<<'\n';std::exit(1);}}
std::vector<uint8_t> run(const std::vector<uint8_t>&s,uint32_t w,uint32_t h,CEOptions o){
 uint32_t x=0,y=0;check(ce_dimensions(w,h,&o,&x,&y)==0,"dimensions");
 std::vector<uint8_t> out(size_t(x)*y*4);check(ce_process(s.data(),w,h,&o,out.data(),out.size())==0,"process");return out;
}
int main(int argc,char**argv){
 (void)argv;
 auto o=ce_defaults();std::vector<uint8_t> s;
 for(int i=0;i<6;++i){s.insert(s.end(),{uint8_t(i*40),uint8_t(i*40),uint8_t(i*40),255});}
 check(run(s,3,2,o)==s,"default is byte-exact identity");
 o.rotation=1;auto r=run(s,3,2,o);
 for(int i=0;i<6;++i)check(r[i*4]==s[std::vector<int>{3,0,4,1,5,2}[i]*4],"90 degree rotation");
 o.rotation=2;r=run(s,3,2,o);for(int i=0;i<6;++i)check(r[i*4]==s[(5-i)*4],"180 degree rotation");
 o.rotation=3;r=run(s,3,2,o);for(int i=0;i<6;++i)check(r[i*4]==s[std::vector<int>{2,5,1,4,0,3}[i]*4],"270 degree rotation");
 o=ce_defaults();o.page=1;r=run(s,3,2,o);check(r.size()==8&&r[0]==0&&r[4]==120,"left page odd width");
 o.page=2;r=run(s,3,2,o);check(r.size()==16&&r[0]==40&&r[12]==200,"right page preserves odd column");
 o=ce_defaults();o.gamma=2;r=run(s,3,2,o);check(r[4]<s[4]&&r[0]==0,"gamma darkens");
 o=ce_defaults();o.brightness=1;r=run(s,3,2,o);check(r[0]==255&&r[20]==255,"brightness clips safely");
 o=ce_defaults();o.grayscale=1;std::vector<uint8_t> rgb={255,0,0,255};r=run(rgb,1,1,o);check(r[0]==54&&r[1]==54&&r[2]==54,"weighted grayscale");
 o=ce_defaults();o.auto_levels=1;r=run(s,3,2,o);check(r.front()==0&&r[20]==255,"histogram stretch");
 std::vector<uint8_t> uniform(9*4,128);for(size_t i=3;i<uniform.size();i+=4)uniform[i]=255;
 o.sharpen=2;o.blur=0.4f;r=run(uniform,3,3,o);check(r==uniform,"uniform image is stable");
 o=ce_defaults();o.scale=2;uint32_t w,h;check(ce_dimensions(3,2,&o,&w,&h)==0&&w==6&&h==4,"resize dimensions");
 r=run(s,3,2,o);check(r[0]==s[0]&&r[r.size()-4]==s[s.size()-4],"resize edge clamping");
 std::mt19937 rng(42);std::vector<uint8_t> random(257*193*4);for(auto &v:random)v=rng()%256;
 for(size_t i=3;i<random.size();i+=4)random[i]=255;
 for(int levels:{2,4,8,16,256}){
   o=ce_defaults();o.levels=levels;o.sharpen=.5;o.blur=.2;
   o.threads=1;auto a=run(random,257,193,o);o.threads=4;auto b=run(random,257,193,o);
   check(a==b,"parallel and serial match");
   for(size_t i=0;i<a.size();i+=4){
     check(a[i]==a[i+1]&&a[i]==a[i+2]&&a[i+3]==255,"grayscale alpha invariant");
     float q=std::round(a[i]*(levels-1)/255.f)*255.f/(levels-1);
     check(std::abs(a[i]-q)<.51f,"quantization on expected grid");
   }
 }
 for(int rotation=0;rotation<4;++rotation)for(int page=0;page<3;++page){
   o=ce_defaults();o.rotation=rotation;o.page=page;o.crop=.2f;o.scale=.7f;
   o.threads=1;auto a=run(random,257,193,o);o.threads=4;check(a==run(random,257,193,o),"geometry determinism");
 }
 o=ce_defaults();uint8_t dest[24];
 check(ce_process(s.data(),3,2,&o,dest,23)==-3,"short buffer rejected");
 check(ce_process(s.data(),3,2,&o,s.data(),s.size())==-1,"alias rejected");
 check(ce_process(nullptr,3,2,&o,dest,24)==-1,"null input rejected");
 check(ce_dimensions(0,1,&o,&w,&h)==-1,"zero width rejected");
 check(ce_dimensions(40000001,1,&o,&w,&h)==-2,"input limit");
 o.scale=2;check(ce_dimensions(10000,2000,&o,&w,&h)==-2,"output limit");
 o.gamma=std::numeric_limits<float>::quiet_NaN();check(ce_dimensions(1,1,&o,&w,&h)==-1,"NaN rejected");
 o=ce_defaults();o.rotation=4;check(ce_dimensions(1,1,&o,&w,&h)==-1,"invalid rotation");
 o=ce_defaults();o.page=1;check(ce_dimensions(1,1,&o,&w,&h)==-1,"impossible split");
 // Impulse must spread with blur and increase local contrast with sharpening.
 std::vector<uint8_t> impulse(5*5*4,0);for(size_t i=3;i<impulse.size();i+=4)impulse[i]=255;
 impulse[(2*5+2)*4]=impulse[(2*5+2)*4+1]=impulse[(2*5+2)*4+2]=128;
 o=ce_defaults();o.blur=1;r=run(impulse,5,5,o);check(r[48]==32&&r[44]>0,"Gaussian blur kernel");
 o.blur=0;o.sharpen=1;r=run(impulse,5,5,o);check(r[48]==224,"unsharp mask kernel");
 std::cout<<"PASS: "<<checks<<" checks\n";
 if(argc>1){
   std::vector<uint8_t> big(3000*4000*4,180);o=ce_defaults();o.auto_levels=1;o.contrast=1.1f;o.sharpen=.4f;
   auto start=std::chrono::steady_clock::now();auto result=run(big,3000,4000,o);
   auto ms=std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now()-start).count();
   std::cout<<"12 MP tone+unsharp: "<<ms<<" ms (host CPU only; not a Mac benchmark), "<<result.size()<<" bytes\n";
 }
}
