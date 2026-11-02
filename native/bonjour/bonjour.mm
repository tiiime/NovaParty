// Apple DNS-SD adapter. No worker threads; callbacks are pumped by exchange().
#import <Foundation/Foundation.h>
#include <dns_sd.h>
#include <arpa/inet.h>
#include <sys/select.h>
#include <map>
#include <memory>
#include <string>
#include <vector>
#include "gdextension_interface.h"
#include "qr_apple.inc.mm"
struct Bonjour;
struct Service { Bonjour *owner; std::string name; DNSServiceRef resolve=nullptr, address=nullptr; bool live=true; NSDictionary *metadata; int port=0; };
struct Bonjour {
 DNSServiceRef browser=nullptr, publisher=nullptr;
 std::map<std::string,std::unique_ptr<Service>> services;
 NSMutableArray *events=[NSMutableArray new];
 void event(NSDictionary *value) { @synchronized(events){[events addObject:value];} }
#if TARGET_OS_IPHONE
 NVQRScanner *scanner;
#endif
 void stopBrowse() { if(browser) DNSServiceRefDeallocate(browser); browser=nullptr; for(auto &p:services){ if(p.second->resolve)DNSServiceRefDeallocate(p.second->resolve); if(p.second->address)DNSServiceRefDeallocate(p.second->address); } services.clear(); }
 ~Bonjour(){ stopBrowse(); if(publisher)DNSServiceRefDeallocate(publisher);
#if TARGET_OS_IPHONE
 NVQRScanner *current=scanner;dispatch_async(dispatch_get_main_queue(),^{[current stop];});
#endif
 }
};
static void addressReply(DNSServiceRef, DNSServiceFlags flags, uint32_t, DNSServiceErrorType error, const char *, const sockaddr *address, uint32_t, void *ctx) {
 auto *s=(Service*)ctx; if(error||!s->live||!(flags&kDNSServiceFlagsAdd)||address->sa_family!=AF_INET)return;
 char ip[INET_ADDRSTRLEN]; inet_ntop(AF_INET,&((const sockaddr_in*)address)->sin_addr,ip,sizeof(ip));
 s->owner->event(@{@"type":@"found", @"key":@(s->name.c_str()), @"address":@(ip), @"port":@(s->port), @"txt":s->metadata?:@{}});
}
static void resolveReply(DNSServiceRef, DNSServiceFlags, uint32_t index, DNSServiceErrorType error, const char *, const char *host, uint16_t port, uint16_t txtLen, const unsigned char *txt, void *ctx) {
 auto *s=(Service*)ctx; if(error||!s->live)return;
 NSMutableDictionary *data=[NSMutableDictionary new];
 for(uint16_t i=0;i<TXTRecordGetCount(txtLen,txt);i++){ char key[256]; uint8_t len=0;const void *value=nullptr;if(TXTRecordGetItemAtIndex(txtLen,txt,i,sizeof(key),key,&len,&value)==0){NSString *v=[[NSString alloc]initWithBytes:value length:len encoding:NSUTF8StringEncoding];if(v)data[@(key)]=v;} }
 s->metadata=data;s->port=ntohs(port);
 DNSServiceErrorType e=DNSServiceGetAddrInfo(&s->address,0,index,kDNSServiceProtocol_IPv4,host,addressReply,s);
 if(e)s->owner->event(@{@"type":@"error",@"code":@(e)});
}
static void browseReply(DNSServiceRef, DNSServiceFlags flags, uint32_t index, DNSServiceErrorType error, const char *name, const char *type, const char *domain, void *ctx) {
 auto *b=(Bonjour*)ctx;if(error){b->event(@{@"type":@"error",@"code":@(error)});return;}
 std::string key=std::string(name)+"/"+std::to_string(index);
 if(!(flags&kDNSServiceFlagsAdd)){auto it=b->services.find(key);if(it!=b->services.end())it->second->live=false;b->event(@{@"type":@"removed",@"key":@(key.c_str())});return;}
 if(b->services.size()>=64||b->services.count(key))return;
 auto service=std::make_unique<Service>();service->owner=b;service->name=key;
 DNSServiceErrorType e=DNSServiceResolve(&service->resolve,0,index,name,type,domain,resolveReply,service.get());
 if(!e)b->services.emplace(key,std::move(service));else b->event(@{@"type":@"error",@"code":@(e)});
}
static void registerReply(DNSServiceRef, DNSServiceFlags, DNSServiceErrorType error, const char *,const char *,const char *,void *ctx){if(error)((Bonjour*)ctx)->event(@{@"type":@"error",@"code":@(error)});}
static NSString *exchange(Bonjour *b, NSString *input) {
 NSDictionary *request=[NSJSONSerialization JSONObjectWithData:[input dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
 if(![request isKindOfClass:NSDictionary.class])request=@{};
 NSString *op=request[@"op"];
 if([op isEqual:@"qr_encode"]){NSString *value=request[@"value"];if([value isKindOfClass:NSString.class]&&value.length<=1024)b->event(@{@"type":@"qr_image",@"data":qrPNG(value)});}
 if([op isEqual:@"qr_decode_image"]){NSString *data=request[@"data"];if([data isKindOfClass:NSString.class]&&data.length<=4000000)b->event(@{@"type":@"qr_decoded",@"value":qrDecode(data)});}
#if TARGET_OS_IPHONE
 if([op isEqual:@"qr_scan"]){NSMutableArray *events=b->events;NVQRScanner *scanner=[NVQRScanner new];scanner.heading=request[@"title"]?:@"Scan to join";scanner.closeText=request[@"close"]?:@"Cancel";scanner.modalPresentationStyle=UIModalPresentationFullScreen;scanner.completion=^(NSString *type,NSString *value){@synchronized(events){[events addObject:@{@"type":type,([type isEqual:@"qr_error"]?@"code":@"value"):value}];}};b->scanner=scanner;dispatch_async(dispatch_get_main_queue(),^{UIViewController *presenter=qrPresenter();if(presenter)[presenter presentViewController:scanner animated:YES completion:nil];else[scanner finish:@"qr_error" value:@"camera_unavailable"];});}
 if([op isEqual:@"qr_stop"]){NVQRScanner *scanner=b->scanner;b->scanner=nil;dispatch_async(dispatch_get_main_queue(),^{[scanner stop];});}
#endif
 if([op isEqual:@"browse"]){b->stopBrowse();DNSServiceErrorType e=DNSServiceBrowse(&b->browser,0,0,"_novaparty._tcp.","local.",browseReply,b);if(e)b->event(@{@"type":@"error",@"code":@(e)});}
 if([op isEqual:@"stop_browse"])b->stopBrowse();
 if([op isEqual:@"stop_advertise"]||[op isEqual:@"advertise"]){if(b->publisher)DNSServiceRefDeallocate(b->publisher);b->publisher=nullptr;}
 if([op isEqual:@"advertise"]){
  TXTRecordRef txt;TXTRecordCreate(&txt,0,nullptr);NSDictionary *metadata=request[@"txt"];
  if([metadata isKindOfClass:NSDictionary.class])for(NSString *key in metadata){NSString *value=[metadata[key]description];NSData *bytes=[value dataUsingEncoding:NSUTF8StringEncoding];if(bytes.length<=200)TXTRecordSetValue(&txt,key.UTF8String,(uint8_t)bytes.length,bytes.bytes);}
  NSString *name=[@"NovaParty-" stringByAppendingString:metadata[@"sid"]?:@"game"];
  DNSServiceErrorType e=DNSServiceRegister(&b->publisher,0,0,name.UTF8String,"_novaparty._tcp.","local.",nullptr,htons([request[@"port"]intValue]),TXTRecordGetLength(&txt),TXTRecordGetBytesPtr(&txt),registerReply,b);TXTRecordDeallocate(&txt);if(e)b->event(@{@"type":@"error",@"code":@(e)});
 }
 std::vector<DNSServiceRef> refs;if(b->browser)refs.push_back(b->browser);if(b->publisher)refs.push_back(b->publisher);
 for(auto &p:b->services){if(p.second->resolve)refs.push_back(p.second->resolve);if(p.second->address)refs.push_back(p.second->address);}
 for(auto ref:refs){int fd=DNSServiceRefSockFD(ref);if(fd<0||fd>=FD_SETSIZE)continue;fd_set set;FD_ZERO(&set);FD_SET(fd,&set);timeval t={0,0};if(select(fd+1,&set,nullptr,nullptr,&t)>0)DNSServiceProcessResult(ref);}
 NSArray *events;@synchronized(b->events){events=[b->events copy];[b->events removeAllObjects];}NSData *data=[NSJSONSerialization dataWithJSONObject:events options:0 error:nil];return [[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding]?:@"[]";
}
// Small C ABI binding keeps this adapter independent of generated godot-cpp bindings.
static GDExtensionClassLibraryPtr library;
static GDExtensionInterfaceGetProcAddress api;
static GDExtensionInterfaceStringNameNewWithUtf8Chars nameNew;
static GDExtensionInterfaceStringNewWithUtf8Chars stringNew;
static GDExtensionInterfaceStringToUtf8Chars stringUtf8;
static GDExtensionInterfaceVariantGetPtrDestructor destructor;
static GDExtensionInterfaceGetVariantFromTypeConstructor fromType;
static GDExtensionInterfaceGetVariantToTypeConstructor toType;
static GDExtensionInterfaceVariantGetType variantType;
static uint64_t className=0,parentName=0,methodName=0,emptyName=0,emptyString=0;
static GDExtensionObjectPtr createInstance(void *,GDExtensionBool){auto object=((GDExtensionInterfaceClassdbConstructObject2)api("classdb_construct_object2"))(&parentName);((GDExtensionInterfaceObjectSetInstance)api("object_set_instance"))(object,&className,new Bonjour());return object;}
static void freeInstance(void *,GDExtensionClassInstancePtr instance){delete (Bonjour*)instance;}
static void invoke(void *,GDExtensionClassInstancePtr instance,const GDExtensionConstVariantPtr *args,GDExtensionInt count,GDExtensionVariantPtr result,GDExtensionCallError *error){
 @autoreleasepool {
  error->error=GDEXTENSION_CALL_OK;NSString *input=@"{}";
  if(count==1&&variantType(args[0])==GDEXTENSION_VARIANT_TYPE_STRING){uint64_t value=0;toType(GDEXTENSION_VARIANT_TYPE_STRING)(&value,(void*)args[0]);auto n=stringUtf8(&value,nullptr,0);std::string bytes(n,'\0');stringUtf8(&value,bytes.data(),n);input=[[NSString alloc]initWithBytes:bytes.data() length:n encoding:NSUTF8StringEncoding];destructor(GDEXTENSION_VARIANT_TYPE_STRING)(&value);}
  NSString *output=exchange((Bonjour*)instance,input);uint64_t value=0;stringNew(&value,output.UTF8String);fromType(GDEXTENSION_VARIANT_TYPE_STRING)(result,&value);destructor(GDEXTENSION_VARIANT_TYPE_STRING)(&value);
 }
}
static void initialize(void *,GDExtensionInitializationLevel level){if(level!=GDEXTENSION_INITIALIZATION_SCENE)return;
 nameNew(&className,"NovaBonjour");nameNew(&parentName,"Object");nameNew(&methodName,"exchange");nameNew(&emptyName,"");stringNew(&emptyString,"");
 GDExtensionClassCreationInfo4 info={};info.is_exposed=true;info.create_instance_func=createInstance;info.free_instance_func=freeInstance;
 ((GDExtensionInterfaceClassdbRegisterExtensionClass4)api("classdb_register_extension_class4"))(library,&className,&parentName,&info);
 GDExtensionPropertyInfo ret={};ret.type=GDEXTENSION_VARIANT_TYPE_STRING;ret.name=&emptyName;ret.class_name=&emptyName;ret.hint_string=&emptyString;
 GDExtensionClassMethodInfo method={};method.name=&methodName;method.call_func=invoke;method.method_flags=GDEXTENSION_METHOD_FLAG_NORMAL|GDEXTENSION_METHOD_FLAG_VARARG;method.has_return_value=true;method.return_value_info=&ret;
 ((GDExtensionInterfaceClassdbRegisterExtensionClassMethod)api("classdb_register_extension_class_method"))(library,&className,&method);
}
static void deinitialize(void *,GDExtensionInitializationLevel level){if(level!=GDEXTENSION_INITIALIZATION_SCENE)return;((GDExtensionInterfaceClassdbUnregisterExtensionClass)api("classdb_unregister_extension_class"))(library,&className);destructor(GDEXTENSION_VARIANT_TYPE_STRING_NAME)(&className);destructor(GDEXTENSION_VARIANT_TYPE_STRING_NAME)(&parentName);destructor(GDEXTENSION_VARIANT_TYPE_STRING_NAME)(&methodName);destructor(GDEXTENSION_VARIANT_TYPE_STRING_NAME)(&emptyName);destructor(GDEXTENSION_VARIANT_TYPE_STRING)(&emptyString);}
extern "C" __attribute__((visibility("default"))) GDExtensionBool novaparty_bonjour_init(GDExtensionInterfaceGetProcAddress get,GDExtensionClassLibraryPtr lib,GDExtensionInitialization *init){
 api=get;library=lib;nameNew=(GDExtensionInterfaceStringNameNewWithUtf8Chars)get("string_name_new_with_utf8_chars");stringNew=(GDExtensionInterfaceStringNewWithUtf8Chars)get("string_new_with_utf8_chars");stringUtf8=(GDExtensionInterfaceStringToUtf8Chars)get("string_to_utf8_chars");destructor=(GDExtensionInterfaceVariantGetPtrDestructor)get("variant_get_ptr_destructor");fromType=(GDExtensionInterfaceGetVariantFromTypeConstructor)get("get_variant_from_type_constructor");toType=(GDExtensionInterfaceGetVariantToTypeConstructor)get("get_variant_to_type_constructor");variantType=(GDExtensionInterfaceVariantGetType)get("variant_get_type");init->minimum_initialization_level=GDEXTENSION_INITIALIZATION_SCENE;init->initialize=initialize;init->deinitialize=deinitialize;return true;
}
