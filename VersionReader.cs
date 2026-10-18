using System;
using System.IO;
using System.Text;
namespace XiaomangUpgrade {
public static class VersionReader {
 public static Version Read(byte[] data) { return new Reader(data).Read(); }
 sealed class Reader {
  byte[] b; int strings,blob; int[] rows=new int[64]; int si,bi,gi;
  public Reader(byte[] data){b=data;}
  int U16(int p){return BitConverter.ToUInt16(b,p);} int I32(int p){return BitConverter.ToInt32(b,p);}
  int Index(int p,int n){return n==2?U16(p):I32(p);} int Id(int t){return rows[t]<65536?2:4;}
  int Code(int bits,params int[] tables){int n=0;foreach(int t in tables)n=Math.Max(n,rows[t]);return n<(1<<(16-bits))?2:4;}
  string Text(int p){int end=p;while(b[end]!=0)end++;return Encoding.UTF8.GetString(b,p,end-p);}
  int Rva(int r,int sections,int count){for(int i=0;i<count;i++){int p=sections+i*40;int start=I32(p+12);if(r>=start&&r<start+Math.Max(I32(p+8),I32(p+16)))return checked(I32(p+20)+r-start);}throw new InvalidDataException("Invalid RVA");}
  public Version Read(){
   int pe=I32(60),optional=pe+24,count=U16(pe+6),sections=optional+U16(pe+20);
   int directory=optional+(U16(optional)==0x20b?112:96);
   int cli=Rva(I32(directory+14*8),sections,count),meta=Rva(I32(cli+8),sections,count);
   if(I32(meta)!=0x424a5342)throw new InvalidDataException("Invalid metadata");
   int p=(meta+16+I32(meta+12)+3)&~3;int streams=U16(p+2);p+=4;int tables=0;
   for(int i=0;i<streams;i++){int offset=I32(p);string name=Text(p+8);if(name=="#Strings")strings=meta+offset;if(name=="#Blob")blob=meta+offset;if(name=="#~"||name=="#-")tables=meta+offset;p=(p+8+name.Length+1+3)&~3;}
   if(tables==0||strings==0||blob==0)throw new InvalidDataException("Missing metadata");
   int heap=b[tables+6];si=(heap&1)!=0?4:2;gi=(heap&2)!=0?4:2;bi=(heap&4)!=0?4:2;
   ulong valid=BitConverter.ToUInt64(b,tables+8);p=tables+24;
   for(int i=0;i<64;i++)if((valid&(1UL<<i))!=0){rows[i]=I32(p);p+=4;}
   int tdor=Code(2,2,1,27);int[] size={2+si+3*gi,Code(2,0,26,35,1)+2*si,4+2*si+tdor+Id(4)+Id(6),Id(4),2+si+bi,Id(6),8+si+bi+Id(8),Id(8),4+si,Id(2)+tdor,Code(3,2,1,26,6,27)+si+bi,2+Code(2,4,8,23)+bi};
   int[] starts=new int[12];for(int i=0;i<12;i++){starts[i]=p;p=checked(p+size[i]*rows[i]);}
   int first=0,last=0;
   for(int i=0;i<rows[2];i++){int q=starts[2]+i*size[2];if(Text(strings+Index(q+4,si))=="Program"&&Text(strings+Index(q+4+si,si))=="ShareX"){first=Index(q+4+2*si+tdor,Id(4));last=i+1<rows[2]?Index(q+size[2]+4+2*si+tdor,Id(4)):rows[4]+1;break;}}
   int majorField=0,minorField=0;
   for(int i=first;i<last;i++){int q=starts[4]+(i-1)*size[4];string name=Text(strings+Index(q+2,si));if(name=="ProductVersionMajor")majorField=i;if(name=="ProductVersionMinor")minorField=i;}
   int major=-1,minor=-1;
   for(int i=0;i<rows[11];i++){int q=starts[11]+i*size[11];int parent=Index(q+2,Code(2,4,8,23));if((parent&3)!=0)continue;int field=parent>>2;if(field!=majorField&&field!=minorField)continue;if(b[q]!=8)throw new InvalidDataException("Version is not Int32");int value=blob+Index(q+2+Code(2,4,8,23),bi);if(b[value]!=4)throw new InvalidDataException("Invalid version value");int n=I32(value+1);if(field==majorField)major=n;else minor=n;}
   if(major<0||minor<0)throw new InvalidDataException("Missing product version constants");return new Version(major,minor);
  }
 }
}}
