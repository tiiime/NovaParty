// NovaParty Link over Bluetooth LE for iOS and macOS (CoreBluetooth). Included by bridge.mm.
// The host is a GATT peripheral, guests are centrals; both directions carry an opaque byte
// stream. Commands arrive from Godot's thread and hop onto one serial queue that also receives
// every CoreBluetooth callback, so link state needs no locks. See docs/bluetooth.md.
#import <CoreBluetooth/CoreBluetooth.h>

@interface NVLane : NSObject
@property(strong) CBPeripheral *peripheral;       // guest side: the host we are connected to
@property(strong) CBCharacteristic *rx;
@property(strong) CBCentral *central;             // host side: one subscribed guest
@property(strong) NSMutableData *pending;
@property NSUInteger flying;
@property BOOL open;
@end
@implementation NVLane
- (instancetype)init { if((self=[super init])) _pending=[NSMutableData new]; return self; }
@end

@interface NVBle : NSObject <CBCentralManagerDelegate, CBPeripheralDelegate, CBPeripheralManagerDelegate>
@property(strong) NSMutableArray *events;
- (void)command:(NSDictionary *)request;
- (void)shutdown;
@end

@implementation NVBle {
 dispatch_queue_t queue;
 CBCentralManager *centralManager;
 CBPeripheralManager *peripheralManager;
 CBUUID *serviceID, *rxID, *txID;
 CBMutableCharacteristic *txCharacteristic;
 NSMutableDictionary<NSString *, CBPeripheral *> *known;
 NSMutableDictionary<NSString *, NSDate *> *seen;
 NSMutableDictionary<NSString *, NVLane *> *remotes;   // key -> host we joined
 NSMutableDictionary<NSString *, NVLane *> *guests;    // key -> subscribed central
 NSMutableSet<NSString *> *disconnecting, *redial;
 NSString *hostName, *lastState;
 BOOL wantScan, wantHost, wantAdvertise, serviceReady;
}
- (instancetype)initWithEvents:(NSMutableArray *)events {
 if((self=[super init])) {
  _events=events; queue=dispatch_queue_create("org.novaparty.ble", DISPATCH_QUEUE_SERIAL);
  serviceID=[CBUUID UUIDWithString:@"6E6F7661-7061-7274-7900-000000000001"];
  rxID=[CBUUID UUIDWithString:@"6E6F7661-7061-7274-7900-000000000002"];
  txID=[CBUUID UUIDWithString:@"6E6F7661-7061-7274-7900-000000000003"];
  known=[NSMutableDictionary new]; seen=[NSMutableDictionary new]; remotes=[NSMutableDictionary new]; guests=[NSMutableDictionary new];
  disconnecting=[NSMutableSet new]; redial=[NSMutableSet new];
 }
 return self;
}
- (void)emit:(NSDictionary *)event { @synchronized(_events){ [_events addObject:event]; } }
- (void)error:(NSString *)code { [self emit:@{@"type":@"ble_error", @"code":code}]; }

// Without the usage description the OS terminates the process on first Bluetooth access
// (editor and headless test runs), so the bridge reports "unsupported" instead.
+ (BOOL)permitted {
#if TARGET_OS_SIMULATOR
 return NO;
#else
 return [NSBundle.mainBundle objectForInfoDictionaryKey:@"NSBluetoothAlwaysUsageDescription"] != nil;
#endif
}
- (void)ensureManagers {
 if(centralManager || ![NVBle permitted]) return;
 NSDictionary *quiet=@{CBCentralManagerOptionShowPowerAlertKey:@NO};
 centralManager=[[CBCentralManager alloc] initWithDelegate:self queue:queue options:quiet];
 peripheralManager=[[CBPeripheralManager alloc] initWithDelegate:self queue:queue options:@{CBPeripheralManagerOptionShowPowerAlertKey:@NO}];
}
- (NSString *)stateName {
 if(![NVBle permitted]) return @"unsupported";
 if(!centralManager) {
  if(@available(iOS 13.1, macOS 10.15, *)) {
   CBManagerAuthorization auth=CBManager.authorization;
   if(auth==CBManagerAuthorizationDenied || auth==CBManagerAuthorizationRestricted) return @"unauthorized";
   if(auth==CBManagerAuthorizationAllowedAlways) { [self ensureManagers]; }
  }
  if(!centralManager) return @"unknown";
 }
 switch(centralManager.state) {
  case CBManagerStatePoweredOn: return @"on";
  case CBManagerStatePoweredOff: return @"off";
  case CBManagerStateUnauthorized: return @"unauthorized";
  case CBManagerStateUnsupported: return @"unsupported";
  default: return @"unknown";
 }
}
- (void)reportState:(BOOL)force {
 NSString *now=[self stateName];
 if(force || ![now isEqual:lastState]) { lastState=now; [self emit:@{@"type":@"ble_state", @"state":now}]; }
}

- (void)command:(NSDictionary *)request { dispatch_async(queue, ^{ [self handle:request]; }); }
- (void)shutdown { dispatch_sync(queue, ^{ [self stopScan]; [self stopHost]; for(NSString *key in remotes.allKeys) [self closeLink:[@"c:" stringByAppendingString:key]]; centralManager.delegate=nil; peripheralManager.delegate=nil; }); }

- (void)handle:(NSDictionary *)request {
 NSString *op=request[@"op"];
 if([op isEqual:@"ble_state"]) { [self reportState:YES]; return; }
 if(![NVBle permitted]) { if([op isEqual:@"ble_connect"]) [self emit:@{@"type":@"ble_closed", @"link":[@"c:" stringByAppendingString:[request[@"key"] description] ?: @""], @"code":@"bluetooth_unsupported"}]; return; }
 if([op isEqual:@"ble_permissions"]) { [self ensureManagers]; [self reportState:YES]; }
 else if([op isEqual:@"ble_host"]) { [self ensureManagers]; [self stopHost]; hostName=[request[@"name"] isKindOfClass:NSString.class] ? request[@"name"] : @"NP"; wantHost=YES; wantAdvertise=YES; [self applyHost]; }
 else if([op isEqual:@"ble_advertise"]) { wantAdvertise=[request[@"enabled"] boolValue]; [self applyAdvertising]; }
 else if([op isEqual:@"ble_host_stop"]) [self stopHost];
 else if([op isEqual:@"ble_scan"]) { [self ensureManagers]; wantScan=YES; [self applyScan]; }
 else if([op isEqual:@"ble_scan_stop"]) [self stopScan];
 else if([op isEqual:@"ble_connect"]) { [self ensureManagers]; [self connect:[request[@"key"] description]]; }
 else if([op isEqual:@"ble_send"]) {
  NSString *encoded=request[@"data"]; NSString *link=request[@"link"];
  NSData *data=[encoded isKindOfClass:NSString.class] ? [[NSData alloc] initWithBase64EncodedString:encoded options:0] : nil;
  if(data.length && [link isKindOfClass:NSString.class]) [self send:data link:link];
 }
 else if([op isEqual:@"ble_close"]) [self closeLink:[request[@"link"] description]];
}

// ---- host (peripheral) -----------------------------------------------------------------
- (void)applyHost {
 if(!wantHost || peripheralManager.state!=CBManagerStatePoweredOn || serviceReady || txCharacteristic) return;
 txCharacteristic=[[CBMutableCharacteristic alloc] initWithType:txID properties:CBCharacteristicPropertyNotify value:nil permissions:CBAttributePermissionsReadable];
 CBMutableCharacteristic *rx=[[CBMutableCharacteristic alloc] initWithType:rxID properties:CBCharacteristicPropertyWrite value:nil permissions:CBAttributePermissionsWriteable];
 CBMutableService *service=[[CBMutableService alloc] initWithType:serviceID primary:YES];
 service.characteristics=@[rx, txCharacteristic];
 [peripheralManager addService:service];
}
- (void)applyAdvertising {
 if(!peripheralManager) return;
 if(peripheralManager.isAdvertising) [peripheralManager stopAdvertising];
 if(wantHost && wantAdvertise && serviceReady && peripheralManager.state==CBManagerStatePoweredOn)
  [peripheralManager startAdvertising:@{CBAdvertisementDataLocalNameKey:hostName ?: @"NP", CBAdvertisementDataServiceUUIDsKey:@[serviceID]}];
}
- (void)stopHost {
 wantHost=NO; wantAdvertise=NO; serviceReady=NO; txCharacteristic=nil; [guests removeAllObjects];
 if(peripheralManager.state==CBManagerStatePoweredOn) { [peripheralManager stopAdvertising]; [peripheralManager removeAllServices]; }
}
- (void)peripheralManagerDidUpdateState:(CBPeripheralManager *)peripheral {
 if(peripheral.state!=CBManagerStatePoweredOn) {
  serviceReady=NO; txCharacteristic=nil;
  for(NSString *key in guests.allKeys) [self emit:@{@"type":@"ble_closed", @"link":[@"p:" stringByAppendingString:key], @"code":@"radio_off"}];
  [guests removeAllObjects];
 }
 [self applyHost];
}
- (void)peripheralManager:(CBPeripheralManager *)peripheral didAddService:(CBService *)service error:(NSError *)error {
 if(error) { txCharacteristic=nil; [self error:@"gatt_server_unavailable"]; return; }
 serviceReady=YES; [self applyAdvertising];
}
- (void)peripheralManagerDidStartAdvertising:(CBPeripheralManager *)peripheral error:(NSError *)error {
 if(!wantHost || !wantAdvertise) return;
 if(error) [self error:@"advertise_failed"];
 else [self emit:@{@"type":@"ble_advertising"}];
}
- (void)peripheralManager:(CBPeripheralManager *)peripheral central:(CBCentral *)central didSubscribeToCharacteristic:(CBCharacteristic *)characteristic {
 NSString *key=central.identifier.UUIDString;
 if(!wantHost || guests[key] || guests.count>=16) return;
 NVLane *lane=[NVLane new]; lane.central=central; lane.open=YES; guests[key]=lane;
 [self emit:@{@"type":@"ble_open", @"link":[@"p:" stringByAppendingString:key]}];
}
- (void)peripheralManager:(CBPeripheralManager *)peripheral central:(CBCentral *)central didUnsubscribeFromCharacteristic:(CBCharacteristic *)characteristic {
 NSString *key=central.identifier.UUIDString;
 if(guests[key]) { [guests removeObjectForKey:key]; [self emit:@{@"type":@"ble_closed", @"link":[@"p:" stringByAppendingString:key], @"code":@"link_lost"}]; }
}
- (void)peripheralManager:(CBPeripheralManager *)peripheral didReceiveWriteRequests:(NSArray<CBATTRequest *> *)requests {
 CBATTError result=CBATTErrorSuccess;
 for(CBATTRequest *request in requests) {
  NSString *key=request.central.identifier.UUIDString;
  // A guest the host has dropped gets a write error and disconnects itself.
  if(![request.characteristic.UUID isEqual:rxID] || !guests[key] || request.offset!=0 || !request.value.length) { result=CBATTErrorWriteNotPermitted; break; }
 }
 if(result==CBATTErrorSuccess) for(CBATTRequest *request in requests)
  [self emit:@{@"type":@"ble_data", @"link":[@"p:" stringByAppendingString:request.central.identifier.UUIDString], @"data":[request.value base64EncodedStringWithOptions:0]}];
 [peripheralManager respondToRequest:requests.firstObject withResult:result];
}
- (void)pumpGuest:(NSString *)key {
 NVLane *lane=guests[key];
 while(lane && txCharacteristic && lane.pending.length) {
  NSUInteger size=MIN(lane.pending.length, MIN((NSUInteger)512, lane.central.maximumUpdateValueLength));
  if(!size) return;
  NSData *chunk=[lane.pending subdataWithRange:NSMakeRange(0, size)];
  if(![peripheralManager updateValue:chunk forCharacteristic:txCharacteristic onSubscribedCentrals:@[lane.central]]) return; // resumes in IsReadyToUpdate
  [lane.pending replaceBytesInRange:NSMakeRange(0, size) withBytes:NULL length:0];
  [self emit:@{@"type":@"ble_sent", @"link":[@"p:" stringByAppendingString:key], @"bytes":@(size)}];
 }
}
- (void)peripheralManagerIsReadyToUpdateSubscribers:(CBPeripheralManager *)peripheral { for(NSString *key in guests.allKeys) [self pumpGuest:key]; }

// ---- guest (central) -------------------------------------------------------------------
- (void)applyScan {
 if(wantScan && centralManager.state==CBManagerStatePoweredOn)
  [centralManager scanForPeripheralsWithServices:@[serviceID] options:@{CBCentralManagerScanOptionAllowDuplicatesKey:@YES}];
}
- (void)stopScan { wantScan=NO; [seen removeAllObjects]; if(centralManager.state==CBManagerStatePoweredOn) [centralManager stopScan]; }
- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
 [self reportState:NO];
 if(central.state!=CBManagerStatePoweredOn) {
  for(NSString *key in [redial setByAddingObjectsFromArray:remotes.allKeys]) [self emit:@{@"type":@"ble_closed", @"link":[@"c:" stringByAppendingString:key], @"code":@"radio_off"}];
  [remotes removeAllObjects]; [disconnecting removeAllObjects]; [redial removeAllObjects];
 }
 [self applyScan];
}
- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary<NSString *,id> *)data RSSI:(NSNumber *)RSSI {
 NSString *name=data[CBAdvertisementDataLocalNameKey];
 NSData *payload=((NSDictionary *)data[CBAdvertisementDataServiceDataKey])[serviceID]; // Android hosts
 if(payload.length>=2 && payload.length<=20) name=[[NSString alloc] initWithData:payload encoding:NSASCIIStringEncoding];
 // CoreBluetooth may omit the local name when it doesn't fit in the advertisement.
 if(!wantScan) return;
 if(![name hasPrefix:@"NP"]) name=@"NP"; // scan is already filtered by our service UUID
 NSString *key=peripheral.identifier.UUIDString;
 NSDate *last=seen[key];
 if(last && -last.timeIntervalSinceNow<1.0) return;
 if(known.count>256) { [known removeAllObjects]; [seen removeAllObjects]; }
 known[key]=peripheral; seen[key]=NSDate.date;
 [self emit:@{@"type":@"ble_found", @"key":key, @"name":name, @"rssi":RSSI ?: @(-100)}];
}
- (void)connect:(NSString *)key {
 // The catalog and join use separate links. Wait for the old disconnect callback
 // so it cannot close a fresh connection with the same peripheral UUID.
 if([disconnecting containsObject:key]) { [redial addObject:key]; return; }
 if(remotes[key]) return;
 NSUUID *identifier=[[NSUUID alloc] initWithUUIDString:key ?: @""];
 CBPeripheral *peripheral=known[key] ?: (identifier ? [centralManager retrievePeripheralsWithIdentifiers:@[identifier]].firstObject : nil);
 if(!peripheral || centralManager.state!=CBManagerStatePoweredOn) { [self emit:@{@"type":@"ble_closed", @"link":[@"c:" stringByAppendingString:key ?: @""], @"code":@"connect_failed"}]; return; }
 NVLane *lane=[NVLane new]; lane.peripheral=peripheral; remotes[key]=lane; known[key]=peripheral;
 peripheral.delegate=self;
 [centralManager connectPeripheral:peripheral options:nil];
}
- (void)failRemote:(CBPeripheral *)peripheral code:(NSString *)code {
 NSString *key=peripheral.identifier.UUIDString;
 if(remotes[key].peripheral!=peripheral) return;
 [self closeLink:[@"c:" stringByAppendingString:key]];
 [self emit:@{@"type":@"ble_closed", @"link":[@"c:" stringByAppendingString:key], @"code":code}];
}
- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral {
 if(remotes[peripheral.identifier.UUIDString].peripheral==peripheral) [peripheral discoverServices:@[serviceID]];
}
- (void)finishedRemote:(CBPeripheral *)peripheral code:(NSString *)code {
 NSString *key=peripheral.identifier.UUIDString;
 if([disconnecting containsObject:key]) {
  [disconnecting removeObject:key];
  if([redial containsObject:key]) { [redial removeObject:key]; [self connect:key]; }
 } else if(remotes[key].peripheral==peripheral) {
  [remotes removeObjectForKey:key];
  [self emit:@{@"type":@"ble_closed", @"link":[@"c:" stringByAppendingString:key], @"code":code}];
 }
}
- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error { [self finishedRemote:peripheral code:@"connect_failed"]; }
- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error { [self finishedRemote:peripheral code:@"link_lost"]; }
- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error {
 for(CBService *service in peripheral.services) if([service.UUID isEqual:serviceID]) { [peripheral discoverCharacteristics:@[rxID, txID] forService:service]; return; }
 [self failRemote:peripheral code:@"service_missing"];
}
- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error {
 NVLane *lane=remotes[peripheral.identifier.UUIDString]; CBCharacteristic *notify=nil;
 for(CBCharacteristic *characteristic in service.characteristics) {
  if([characteristic.UUID isEqual:rxID]) lane.rx=characteristic;
  if([characteristic.UUID isEqual:txID]) notify=characteristic;
 }
 if(!lane || !lane.rx || !notify) { [self failRemote:peripheral code:@"service_missing"]; return; }
 [peripheral setNotifyValue:YES forCharacteristic:notify];
}
- (void)peripheral:(CBPeripheral *)peripheral didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
 NSString *key=peripheral.identifier.UUIDString; NVLane *lane=remotes[key];
 if(!lane || lane.peripheral!=peripheral) return;
 if(error || !characteristic.isNotifying) { [self failRemote:peripheral code:lane.open ? @"link_lost" : @"subscribe_failed"]; return; }
 if(lane.open) return;
 lane.open=YES; [self emit:@{@"type":@"ble_open", @"link":[@"c:" stringByAppendingString:key]}]; [self pumpRemote:key];
}
- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
 NSString *key=peripheral.identifier.UUIDString;
 if(!error && remotes[key].peripheral==peripheral && characteristic.value.length)
  [self emit:@{@"type":@"ble_data", @"link":[@"c:" stringByAppendingString:key], @"data":[characteristic.value base64EncodedStringWithOptions:0]}];
}
- (void)peripheral:(CBPeripheral *)peripheral didWriteValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
 NSString *key=peripheral.identifier.UUIDString; NVLane *lane=remotes[key];
 if(!lane || lane.peripheral!=peripheral) return;
 if(error) { [self failRemote:peripheral code:@"write_failed"]; return; }
 [self emit:@{@"type":@"ble_sent", @"link":[@"c:" stringByAppendingString:key], @"bytes":@(lane.flying)}];
 lane.flying=0; [self pumpRemote:key];
}
- (void)pumpRemote:(NSString *)key {
 NVLane *lane=remotes[key];
 if(!lane || !lane.open || lane.flying || !lane.pending.length) return;
 NSUInteger limit=MIN((NSUInteger)512, MAX((NSUInteger)20, [lane.peripheral maximumWriteValueLengthForType:CBCharacteristicWriteWithResponse]));
 NSUInteger size=MIN(lane.pending.length, limit);
 NSData *chunk=[lane.pending subdataWithRange:NSMakeRange(0, size)];
 [lane.pending replaceBytesInRange:NSMakeRange(0, size) withBytes:NULL length:0];
 lane.flying=size;
 [lane.peripheral writeValue:chunk forCharacteristic:lane.rx type:CBCharacteristicWriteWithResponse];
}

// ---- shared ----------------------------------------------------------------------------
- (void)send:(NSData *)data link:(NSString *)link {
 if(link.length<3) return;
 NSString *key=[link substringFromIndex:2];
 NVLane *lane=[link hasPrefix:@"p:"] ? guests[key] : [link hasPrefix:@"c:"] ? remotes[key] : nil;
 if(!lane) return;
 if(lane.pending.length+data.length>262144) { [self closeLink:link]; [self emit:@{@"type":@"ble_closed", @"link":link, @"code":@"queue_overflow"}]; return; }
 [lane.pending appendData:data];
 if([link hasPrefix:@"p:"]) [self pumpGuest:key]; else [self pumpRemote:key];
}
// Local close: Godot already forgot the link, so no ble_closed event is queued.
- (void)closeLink:(NSString *)link {
 if(link.length<3) return;
 NSString *key=[link substringFromIndex:2];
 if([link hasPrefix:@"p:"]) [guests removeObjectForKey:key]; // CoreBluetooth cannot disconnect a central
 else if([link hasPrefix:@"c:"]) {
  [redial removeObject:key];
  NVLane *lane=remotes[key];
  if(lane) {
   [remotes removeObjectForKey:key];
   if(lane.peripheral.state!=CBPeripheralStateDisconnected) {
    [disconnecting addObject:key];
    [centralManager cancelPeripheralConnection:lane.peripheral];
   }
  }
 }
}
@end
