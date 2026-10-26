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

void advancedTests(){
 auto o=ce_defaults();
 auto rgba=[](const std::vector<uint8_t>&gray){std::vector<uint8_t> out(gray.size()*4,255);for(size_t i=0;i<gray.size();++i)out[i*4]=out[i*4+1]=out[i*4+2]=gray[i];return out;};
 std::vector<uint8_t> ramp(256);for(int i=0;i<256;++i)ramp[i]=i;
 o.binarization=1;o.threshold=100;auto result=run(rgba(ramp),256,1,o);
 for(int i=0;i<256;++i)check(result[i*4]==(i<=100?0:255),"fixed threshold exact");
 o.binarization=2;std::vector<uint8_t> two(200,220);std::fill(two.begin(),two.begin()+100,30);
 result=run(rgba(two),20,10,o);for(int i=0;i<200;++i)check(result[i*4]==(i<100?0:255),"Otsu separates bimodal values");
 result=run(rgba(std::vector<uint8_t>(400,200)),20,20,o);check(result[0]==255,"uniform Otsu blank stays white");
 // Compare rolling-window Sauvola against an independent brute-force reference.
 std::vector<uint8_t> shadow(37*29);for(int y=0;y<29;++y)for(int x=0;x<37;++x)shadow[y*37+x]=uint8_t(80+x*4-((x%7<2&&y%8<5)?65:0));
 for(int radius:{1,4,100}){
   o=ce_defaults();o.binarization=3;o.adaptive_radius=radius;o.sauvola_k=.25f;
   result=run(rgba(shadow),37,29,o);
   for(int y=0;y<29;++y)for(int x=0;x<37;++x){double sum=0,sq=0,n=0;
     for(int yy=std::max(0,y-radius);yy<=std::min(28,y+radius);++yy)for(int xx=std::max(0,x-radius);xx<=std::min(36,x+radius);++xx){double v=shadow[yy*37+xx];sum+=v;sq+=v*v;++n;}
     double mean=sum/n,t=mean*(1+.25*(std::sqrt(std::max(0.,sq/n-mean*mean))/128-1));
     check(result[(y*37+x)*4]==(shadow[y*37+x]<=t?0:255),"Sauvola matches brute force at edges");
   }
 }
 std::vector<uint8_t> noise(15*15,255);noise[7*15+7]=0;
 o=ce_defaults();o.binarization=1;o.cleanup=1;result=run(rgba(noise),15,15,o);check(result[(7*15+7)*4]==255,"isolated ink removed");
 noise[7*15+8]=0;result=run(rgba(noise),15,15,o);check(result[(7*15+7)*4]==0,"connected thin pair preserved");
 std::fill(noise.begin(),noise.end(),255);
 for(int y=5;y<=9;++y)for(int x=5;x<=9;++x)noise[y*15+x]=0;
 noise[4*15+7]=0;o.cleanup=3;result=run(rgba(noise),15,15,o);
 check(result[(4*15+7)*4]==255&&result[(7*15+7)*4]==0,"opening removes protrusion preserving core");
 noise[4*15+7]=255;noise[7*15+7]=255;o.cleanup=4;result=run(rgba(noise),15,15,o);check(result[(7*15+7)*4]==0,"closing repairs hole");
 o.cleanup=2;noise.assign(225,255);noise[7*15+7]=0;result=run(rgba(noise),15,15,o);check(result[(7*15+7)*4]==255,"majority clears isolated dot");
 o=ce_defaults();o.blur=1;o.blur_method=2;result=run(rgba(noise),15,15,o);check(result[(7*15+7)*4]==255,"median removes salt-and-pepper noise");
 std::vector<uint8_t> edge(32*16);for(int y=0;y<16;++y)for(int x=0;x<32;++x)edge[y*32+x]=x<16?20:230;
 o.blur_method=3;o.edge_sigma=10;o.filter_radius=3;result=run(rgba(edge),32,16,o);
 check(result[(8*32+15)*4]==20&&result[(8*32+16)*4]==230,"bilateral preserves strong edge");
 o.blur_method=1;o.filter_radius=1;result=run(rgba(edge),32,16,o);check(result[(8*32+15)*4]==90,"box filter known edge mean");
 o=ce_defaults();o.sharpen=1;o.sharpen_method=1;result=run(rgba(edge),32,16,o);check(result[(8*32+15)*4]==0&&result[(8*32+16)*4]==255,"Laplacian enhances edge");
 o.sharpen_threshold=255;check(run(rgba(edge),32,16,o)==rgba(edge),"sharpen threshold protects weak edges");
 for(int dither:{0,1,2}){o=ce_defaults();o.levels=4;o.dither=dither;result=run(rgba(ramp),16,16,o);
   for(size_t i=0;i<result.size();i+=4)check(result[i]%85==0,"dither stays on quantization grid");}
 o=ce_defaults();o.levels=2;o.dither=2;auto mid=run(rgba(std::vector<uint8_t>(128*128,128)),128,128,o);
 int whites=0;for(size_t i=0;i<mid.size();i+=4)whites+=mid[i]==255;
 check(std::abs(whites/16384.-128/255.)<.02,"error diffusion preserves average tone");
 // Both canvas orientations and both text layouts; clockwise input needs negative correction.
 for(bool vertical:{false,true})for(bool landscape:{false,true})for(float angle:{-3.25f,0.f,3.25f}){
   int w=landscape?600:400,h=landscape?400:600;std::vector<uint8_t> page(w*h,255);
   for(int y=50;y<h-50;++y)for(int x=50;x<w-50;++x){
     bool ink=vertical?((x-50)%28<5&&(y-50)%13<8):((y-50)%28<5&&(x-50)%13<8);
     if(ink)page[y*w+x]=20;
   }
   o=ce_defaults();o.angle=angle;auto tilted=run(rgba(page),w,h,o);float correction=0;
   check(ce_estimate_skew(tilted.data(),w,h,vertical,5,&correction)==0,"skew estimate success");
   if(std::abs(correction+angle)>.22f)std::cerr<<"skew: "<<vertical<<","<<landscape<<","<<angle<<" => "<<correction<<"\n";
   check(std::abs(correction+angle)<.22f,"horizontal and vertical skew accuracy");
   o=ce_defaults();o.deskew=vertical?2:1;auto aligned=run(tilted,w,h,o);float residual=9;
   check(ce_estimate_skew(aligned.data(),w,h,vertical,5,&residual)==0&&std::abs(residual)<.22f,"automatic correction removes skew");
 }
 auto blank=rgba(std::vector<uint8_t>(10000,255));float correction=9;
 check(ce_estimate_skew(blank.data(),100,100,0,5,&correction)==0&&correction==0,"blank page not rotated");
 // All expensive modes must remain deterministic across stripe boundaries.
 std::vector<uint8_t> stripes(131*197);for(size_t i=0;i<stripes.size();++i)stripes[i]=(i*71)%256;
 for(int method=0;method<4;++method){o=ce_defaults();o.blur=0.7f;o.blur_method=method;o.filter_radius=2;o.binarization=3;o.cleanup=2;
   o.threads=1;auto a=run(rgba(stripes),131,197,o);o.threads=4;check(a==run(rgba(stripes),131,197,o),"advanced parallel determinism");}
 uint32_t w,h;o=ce_defaults();o.filter_radius=4;check(ce_dimensions(1,1,&o,&w,&h)==-1,"invalid filter radius rejected");
 o=ce_defaults();o.angle=std::numeric_limits<float>::infinity();check(ce_dimensions(1,1,&o,&w,&h)==-1,"infinite angle rejected");
 // Tiny pages, oversized adaptive windows, and all cleanup/filter combinations must be safe.
 for(int bw=1;bw<=2;++bw)for(int bh=1;bh<=2;++bh)for(int method=0;method<4;++method)for(int cleanup=0;cleanup<5;++cleanup){
   o=ce_defaults();o.blur=1;o.blur_method=method;o.filter_radius=3;o.binarization=3;o.adaptive_radius=100;o.cleanup=cleanup;
   auto tiny=run(rgba(std::vector<uint8_t>(bw*bh,180)),bw,bh,o);check(tiny.size()==size_t(bw*bh*4),"tiny image edge safety");
 }
}

void pageTests(){
 auto rgba=[](const std::vector<uint8_t>&gray){std::vector<uint8_t> out(gray.size()*4,255);for(size_t i=0;i<gray.size();++i)out[i*4]=out[i*4+1]=out[i*4+2]=gray[i];return out;};
 std::vector<uint8_t> values={0,40,80,120,160,200,240,255};auto source=rgba(values);
 for(int method=0;method<3;++method){
   std::vector<uint8_t> result(source.size());float rect[4]={0,0,4,2};
   check(ce_canvas(source.data(),4,2,4,2,rect,method,result.data(),result.size())==0,"canvas succeeds");
   check(result==source,"every resampler has exact identity at integer samples");
 }
 std::vector<uint8_t> canvas(6*4*4,255);auto black=rgba(std::vector<uint8_t>(4*2,0));
 check(ce_blit(black.data(),4,2,canvas.data(),6,4,1,1,canvas.size())==0,"native blit");
 check(canvas[0]==255&&canvas[(1*6+1)*4]==0,"native blit preserves other canvas pixels");
 float inner[4]={2,1,2,2};check(ce_whiten_outside(canvas.data(),6,4,inner)==0&&canvas[(1*6+1)*4]==255&&canvas[(1*6+2)*4]==0,"page margins mask overflow");
 check(ce_blit(black.data(),4,2,canvas.data(),6,4,4,1,canvas.size())==-2,"out of bounds blit rejected");
 std::vector<uint8_t> result(6*4*4);float padded[4]={1,1,4,2};
 check(ce_canvas(source.data(),4,2,6,4,padded,2,result.data(),result.size())==0,"padded canvas");
 check(result[0]==255&&result[(1*6+1)*4]==0&&result[(2*6+4)*4]==255,"white margin and content placement");
 float clipped[4]={-1,0,4,2};result.resize(2*2*4);
 check(ce_canvas(source.data(),4,2,2,2,clipped,1,result.data(),result.size())==0,"overflow crop");
 check(result[0]==40&&result[4]==80&&result[8]==200,"overflow pixels sampled in top-left coordinates");
 float farAway[4]={1.e9f,1.e9f,1.e-20f,1.e-20f};
 check(ce_canvas(source.data(),4,2,2,2,farAway,2,result.data(),result.size())==0&&result[0]==255,"outside canvas does not overflow sample indices");
 check(ce_canvas(source.data(),4,2,2,2,clipped,1,result.data(),1)==-3,"canvas capacity check");
 auto mirrored=source;check(ce_mirror(source.data(),4,2,1,1,mirrored.data(),mirrored.size())==0,"mirror succeeds");
 for(int i=0;i<8;++i)check(mirrored[i*4]==values[7-i],"mirror both axes");
 check(ce_invert(mirrored.data(),4,2)==0&&ce_invert(mirrored.data(),4,2)==0,"invert succeeds");
 std::vector<uint8_t> dots(20*20,255);
 for(int y=2;y<4;++y)for(int x=2;x<4;++x)dots[y*20+x]=0;
 for(int x=8;x<13;++x)dots[10*20+x]=0;
 dots[15*20+15]=180;auto data=rgba(dots);
 check(ce_despeckle(data.data(),20,20,2,127,0)==0,"connected despeckle");
 check(data[(2*20+2)*4]==255&&data[(10*20+8)*4]==0&&data[(15*20+15)*4]==180,"remove only small dark bounding boxes, keep long strokes and pale pixels");
 check(ce_despeckle(data.data(),20,20,2,200,0)==0&&data[(15*20+15)*4]==255,"gray threshold is adjustable");
 dots.assign(400,255);for(int y=0;y<8;++y)dots[y*20+5]=0;dots[12*20+12]=0;data=rgba(dots);
 check(ce_despeckle(data.data(),20,20,0,127,1)==0&&data[5*4]==255&&data[(12*20+12)*4]==0,"border removal does not remove detached foreground");
 dots.assign(400,255);dots[1*20+1]=0;for(int y=6;y<12;++y)for(int x=8;x<15;++x)dots[y*20+x]=0;data=rgba(dots);uint32_t bounds[4];
 check(ce_content_bounds(data.data(),20,20,127,1,bounds)==0,"content bounds");
 check(bounds[0]==8&&bounds[1]==6&&bounds[2]==7&&bounds[3]==6,"content bounds ignore small marks");
 data=rgba(std::vector<uint8_t>(400,255));check(ce_content_bounds(data.data(),20,20,127,0,bounds)==0&&bounds[2]==20&&bounds[3]==20,"blank page bounds stay whole");
 dots.assign(400,255);for(int y=6;y<12;++y)for(int x=6;x<12;++x)dots[y*20+x]=0;dots[5*20+8]=0;dots[9*20+9]=255;
 data=rgba(dots);check(ce_smooth_binary(data.data(),20,20,1,0)==0,"template smoothing");
 check(data[(5*20+8)*4]==255&&data[(9*20+9)*4]==255&&data[(6*20+8)*4]==0,"templates remove protrusion without filling an enclosed hole or eroding the body");
 dots.assign(400,255);for(int i=3;i<17;++i){dots[10*20+i]=0;dots[i*20+i]=0;}auto thin=rgba(dots);data=thin;
 check(ce_smooth_binary(data.data(),20,20,3,1)==0&&data==thin,"thin strokes and endpoints survive repeated smoothing");
 data=rgba(std::vector<uint8_t>(400,128));check(ce_smooth_binary(data.data(),20,20,1,0)==-1,"nonbinary smoothing rejected");
}
// Independent, deliberately simple reference kernels protect the optimized
// integer/sliding implementations against border and stripe-boundary mistakes.
void optimizedKernelTests(){
 std::mt19937 rng(97531);
 for(int w:{1,2,17})for(int h:{1,137}){
  std::vector<uint8_t> src(size_t(w)*h*4,255);
  for(size_t i=0;i<src.size();++i)if(i%4!=3)src[i]=rng()%256;
  for(int method=0;method<3;++method)for(int radius=1;radius<=3;++radius){
   auto o=ce_defaults();o.blur=1;o.blur_method=method;o.filter_radius=radius;o.threads=4;
   auto actual=run(src,w,h,o),expected=src,tmp=src;
   if(method<2){
    std::vector<float> weights(2*radius+1,1);float total=0;
    for(int i=0;i<=2*radius;++i){if(!method)for(int j=1;j<=i;++j)weights[i]*=float(2*radius-j+1)/j;total+=weights[i];}
    for(auto &v:weights)v/=total;
    for(int pass=0;pass<2;++pass){auto &input=pass?tmp:src;auto &out=pass?expected:tmp;
     for(int y=0;y<h;++y)for(int x=0;x<w;++x)for(int c=0;c<3;++c){float sum=0;
      for(int d=-radius;d<=radius;++d){int xx=pass?x:std::clamp(x+d,0,w-1),yy=pass?std::clamp(y+d,0,h-1):y;
       sum+=input[(size_t(yy)*w+xx)*4+c]*weights[d+radius];}
      out[(size_t(y)*w+x)*4+c]=uint8_t(std::lround(sum));
     }
    }
   }else{
    for(int y=0;y<h;++y)for(int x=0;x<w;++x)for(int c=0;c<3;++c){std::vector<uint8_t> window;
     for(int dy=-radius;dy<=radius;++dy)for(int dx=-radius;dx<=radius;++dx)
      window.push_back(src[(size_t(std::clamp(y+dy,0,h-1))*w+std::clamp(x+dx,0,w-1))*4+c]);
     std::sort(window.begin(),window.end());expected[(size_t(y)*w+x)*4+c]=window[window.size()/2];
    }
   }
   check(actual==expected,"optimized filters match independent reference including tiny edges and parallel stripes");
  }
 }
 auto cubic=[](float x){x=std::abs(x);return x<1?(1.5f*x-2.5f)*x*x+1:x<2?((-.5f*x+2.5f)*x-4)*x+2:0;};
 for(int method=0;method<3;++method)for(int trial=0;trial<15;++trial){
  int w=1+rng()%35,h=1+rng()%37,ow=1+rng()%51,oh=1+rng()%151;
  std::vector<uint8_t> src(w*h*4),out(ow*oh*4);for(auto &v:src)v=rng()%256;
  float r[]={float(int(rng()%20)-10),float(int(rng()%20)-10),float(1+rng()%60),float(1+rng()%60)};
  check(ce_canvas(src.data(),w,h,ow,oh,r,method,out.data(),out.size())==0,"optimized resampler returns success");
  for(int y=0;y<oh;++y)for(int x=0;x<ow;++x)for(int c=0;c<4;++c){
   int expected=255;
   if(c<3&&x+.5f>=r[0]&&x+.5f<r[0]+r[2]&&y+.5f>=r[1]&&y+.5f<r[1]+r[3]){
    double sx=(x+.5-r[0])*w/r[2]-.5,sy=(y+.5-r[1])*h/r[3]-.5;
    int bx=int(std::floor(sx)),by=int(std::floor(sy));
    if(!method)expected=src[(size_t(std::clamp(int(std::lround(sy)),0,h-1))*w+std::clamp(int(std::lround(sx)),0,w-1))*4+c];
    else {float value=0;int taps=method==1?2:4;
     for(int yy=0;yy<taps;++yy)for(int xx=0;xx<taps;++xx){int ix=bx+xx-(method==2),iy=by+yy-(method==2);
      float wx=method==1?(xx?float(sx-bx):1-float(sx-bx)):cubic(float(sx-ix));
      float wy=method==1?(yy?float(sy-by):1-float(sy-by)):cubic(float(sy-iy));
      value+=src[(size_t(std::clamp(iy,0,h-1))*w+std::clamp(ix,0,w-1))*4+c]*wx*wy;
     }expected=int(std::lround(std::clamp(value,0.f,255.f)));
    }
   }
   check(std::abs(int(out[(size_t(y)*ow+x)*4+c])-expected)<=1,"separable canvas agrees with direct 2D reference within one intensity level");
  }
 }
 for(int pattern=0;pattern<512;++pattern)for(int fill:{0,1}){
  std::vector<uint8_t> src(5*5*4,255);
  for(int j=0;j<9;++j)if(pattern&(1<<j))for(int c=0;c<3;++c)src[((j/3+1)*5+j%3+1)*4+c]=0;
  auto expected=src,actual=src;
  for(int pass=0;pass<3;++pass){auto input=expected;
   for(int y=1;y<4;++y)for(int x=1;x<4;++x){bool center=input[(y*5+x)*4]==0;if(!center&&!fill)continue;
    for(int turn=0;turn<4;++turn){bool match=true;
     for(int dy=-1;dy<=1;++dy)for(int dx=-1;dx<=1;++dx){if(!dx&&!dy)continue;int xx=dx,yy=dy;
      for(int k=0;k<turn;++k){int old=xx;xx=-yy;yy=old;}
      bool want=dy==1;if(!center)want=!want;
      if((input[((y+yy)*5+x+xx)*4]==0)!=want)match=false;
     }
     if(match){for(int c=0;c<3;++c)expected[(y*5+x)*4+c]=center?255:0;break;}
    }
   }
  }
  check(ce_smooth_binary(actual.data(),5,5,3,fill)==0&&actual==expected,"all 512 binary neighborhoods retain the original rotated-template behavior");
 }
}
void grayTests(){
 std::mt19937 rng(86420);auto workspace=ce_gray_workspace_create();check(workspace!=nullptr,"gray workspace created");
 for(int trial=0;trial<100;++trial){uint32_t w=1+rng()%37,h=trial%3==0?197:1+rng()%29;
  std::vector<uint8_t> gray(size_t(w)*h),rgba(gray.size()*4,255);for(size_t i=0;i<gray.size();++i){gray[i]=rng()%256;rgba[i*4]=rgba[i*4+1]=rgba[i*4+2]=gray[i];}
  auto o=ce_defaults();o.rotation=trial%4;o.auto_levels=trial%2;o.brightness=.03f;o.contrast=1.1f;o.gamma=1.1f;
  o.blur=trial%2?.3f:0;o.blur_method=trial%2;o.filter_radius=trial%3+1;o.sharpen=.6f;o.sharpen_method=trial%2;o.sharpen_threshold=2;
  o.binarization=trial%4;o.adaptive_radius=trial%3==0?100:20;o.threads=trial%2?1:4;
  if(!o.binarization){o.levels=4;o.dither=trial%3;}
  uint32_t ow,oh;check(ce_dimensions(w,h,&o,&ow,&oh)==0,"gray dimensions");
  auto reference=run(rgba,w,h,o);std::vector<uint8_t> result(size_t(ow)*oh);
  for(int backend:{1,2}){ce_gray_workspace_backend(workspace,backend);
   check(ce_process_gray(gray.data(),w,h,&o,result.data(),result.size(),workspace)==0,"gray processor success");
   for(size_t i=0;i<result.size();++i){if(result[i]!=reference[i*4])std::cerr<<"gray trial="<<trial<<" backend="<<backend<<" i="<<i<<" actual="<<int(result[i])<<" expected="<<int(reference[i*4])<<"\n";
    check(result[i]==reference[i*4],"Gray8 equals RGBA through LUT, convolution, rotation, threshold and diffusion");}
  }
  std::vector<uint8_t> compact(gray.size()),expanded(rgba.size());
  check(ce_gray_from_rgba(rgba.data(),w,h,compact.data(),compact.size())==0&&compact==gray,"gray extraction exact");
  check(ce_gray_to_rgba(gray.data(),w,h,expanded.data(),expanded.size())==0&&expanded==rgba,"gray expansion exact");
  for(int method=0;method<3;++method){uint32_t cw=w+7,ch=h+5;float rect[]={2,1,float(w)*1.3f,float(h)*1.2f};std::vector<uint8_t> a(size_t(cw)*ch),b(a.size()*4);
   check(ce_canvas_gray(gray.data(),w,h,cw,ch,rect,method,a.data(),a.size())==0&&ce_canvas(rgba.data(),w,h,cw,ch,rect,method,b.data(),b.size())==0,"gray canvas success");
   for(size_t i=0;i<a.size();++i)check(a[i]==b[i*4],"gray canvas samples equal RGBA");
  }
  for(int bits:{1,2,4,8}){size_t stride=(w*bits+7)/8;std::vector<uint8_t> packed(stride*h,0);
   check(ce_gray_pack(gray.data(),w,h,bits,packed.data(),packed.size())==0,"gray bit packing success");
   for(uint32_t y=0;y<h;++y)for(uint32_t x=0;x<w;++x){int value=(packed[size_t(y)*stride+x*bits/8]>>(8-bits-x*bits%8))&((1<<bits)-1);
    check(value==(int(gray[size_t(y)*w+x])*((1<<bits)-1)+127)/255,"gray packing preserves quantization");}
  }
  std::vector<uint8_t> binary(gray.size()),binaryRGBA(rgba.size(),255);
  for(size_t i=0;i<gray.size();++i){binary[i]=gray[i]<=127?0:255;binaryRGBA[i*4]=binaryRGBA[i*4+1]=binaryRGBA[i*4+2]=binary[i];}
  check(ce_smooth_binary_gray(binary.data(),w,h,3,1)==0&&ce_smooth_binary(binaryRGBA.data(),w,h,3,1)==0,"gray templates success");
  for(size_t i=0;i<gray.size();++i)check(binary[i]==binaryRGBA[i*4],"gray templates equal RGBA");
  auto original=gray;auto originalRGBA=rgba;
  check(ce_despeckle_gray(gray.data(),w,h,2,127,1)==0&&ce_despeckle(rgba.data(),w,h,2,127,1)==0,"gray components success");
  for(size_t i=0;i<gray.size();++i)check(gray[i]==rgba[i*4],"gray components equal RGBA");
  uint32_t a[4],b[4];check(ce_content_bounds_gray(original.data(),w,h,127,trial%3,a)==0&&ce_content_bounds(originalRGBA.data(),w,h,127,trial%3,b)==0&&std::equal(a,a+4,b),"gray content bounds equal RGBA");
 }
 auto o=ce_defaults();uint8_t src[]={10,20,30,255},dst[4];
 check(ce_gray_from_rgba(src,1,1,dst,1)==-5,"color is never silently treated as gray");
 check(ce_process_gray(src,1,1,&o,dst,0,workspace)==-3,"gray output capacity checked");
 o.blur=1;o.blur_method=3;check(!ce_gray_supported(&o)&&ce_process_gray(src,1,1,&o,dst,1,workspace)==-5,"unsupported gray mode requests RGBA fallback");
 std::vector<uint8_t> table(65536);
 for(float amount:{.1f,.3f,.37f,.6f,1.13f,1.99f})for(float threshold:{0.f,2.3f,255.f})for(int sharp:{0,1}){
  check(ce_gray_blend_table(amount,threshold,sharp,table.data(),table.size())==0,"blend table created");
  for(int original=0;original<256;++original)for(int soft=0;soft<256;++soft){
   float delta=original-float(soft),value=sharp?(std::abs(delta)>=threshold?original+amount*delta:float(original)):original+(soft-float(original))*amount;
   check(table[original*256+soft]==uint8_t(std::lround(std::clamp(value,0.f,255.f))),"all byte-pair blend entries preserve float formula");
  }
 }
 ce_gray_workspace_destroy(workspace);
 check(ce_set_thread_budget(2)==0&&ce_set_thread_budget(0)==2,"page thread budget restores correctly");
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
 check(ce_dimensions(100000001,1,&o,&w,&h)==-2,"input limit");
 o.scale=2;check(ce_dimensions(20000,2000,&o,&w,&h)==-2,"output limit");
 o.gamma=std::numeric_limits<float>::quiet_NaN();check(ce_dimensions(1,1,&o,&w,&h)==-1,"NaN rejected");
 o=ce_defaults();o.rotation=4;check(ce_dimensions(1,1,&o,&w,&h)==-1,"invalid rotation");
 o=ce_defaults();o.page=1;check(ce_dimensions(1,1,&o,&w,&h)==-1,"impossible split");
 // Impulse must spread with blur and increase local contrast with sharpening.
 std::vector<uint8_t> impulse(5*5*4,0);for(size_t i=3;i<impulse.size();i+=4)impulse[i]=255;
 impulse[(2*5+2)*4]=impulse[(2*5+2)*4+1]=impulse[(2*5+2)*4+2]=128;
 o=ce_defaults();o.blur=1;r=run(impulse,5,5,o);check(r[48]==32&&r[44]>0,"Gaussian blur kernel");
 o.blur=0;o.sharpen=1;r=run(impulse,5,5,o);check(r[48]==224,"unsharp mask kernel");
 advancedTests();
 pageTests();
 optimizedKernelTests();
 grayTests();
 std::cout<<"PASS: "<<checks<<" checks\n";
 if(argc>1){
   std::vector<uint8_t> big(3000*4000*4,255);
   for(int y=0;y<4000;++y)for(int x=0;x<3000;++x){
     uint8_t value=uint8_t((x%19<3&&y%31<13?35:180)+(x*17+y*31)%35);
     size_t i=(size_t(y)*3000+x)*4;big[i]=big[i+1]=big[i+2]=value;
   }
   o=ce_defaults();o.auto_levels=1;o.contrast=1.1f;o.sharpen=.4f;
   auto start=std::chrono::steady_clock::now();auto result=run(big,3000,4000,o);
   auto ms=std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now()-start).count();
   std::cout<<"12 MP tone+unsharp: "<<ms<<" ms (current runner CPU; includes allocation, excludes codec/UI), "<<result.size()<<" bytes\n";
   big.resize(1500*2000*4);
   for(int mode=0;mode<6;++mode){o=ce_defaults();
     if(mode<4){o.blur=1;o.blur_method=mode;o.filter_radius=2;}
     else {o.binarization=mode==4?2:3;o.adaptive_radius=20;o.cleanup=1;}
     auto begin=std::chrono::steady_clock::now();auto processed=run(big,1500,2000,o);
     auto elapsed=std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now()-begin).count();
     std::cout<<"3 MP "<<std::vector<const char*>{"Gaussian","Box","Median","Bilateral","Otsu+cleanup","Sauvola+cleanup"}[mode]<<": "<<elapsed<<" ms\n";
   }

 }
}
