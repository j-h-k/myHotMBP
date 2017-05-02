//
//  AppDelegate.m
//  testhot
//
//  Created by jae on 4/14/17.
//  Copyright © 2017 jae. All rights reserved.
//

#import "AppDelegate.h"
//#include <stdio.h>
//#include <string.h>
//#include <IOKit/IOKitLib.h>

#include "smc.h"

static io_connect_t conn;

UInt32 _strtoul(char *str, int size, int base)
{
    UInt32 total = 0;
    int i;
    
    for (i = 0; i < size; i++)
    {
        if (base == 16)
            total += str[i] << (size - 1 - i) * 8;
        else
            total += (unsigned char) (str[i] << (size - 1 - i) * 8);
    }
    return total;
}

void _ultostr(char *str, UInt32 val)
{
    str[0] = '\0';
    sprintf(str, "%c%c%c%c",
            (unsigned int) val >> 24,
            (unsigned int) val >> 16,
            (unsigned int) val >> 8,
            (unsigned int) val);
}

kern_return_t SMCOpen(void)
{
    kern_return_t result;
    io_iterator_t iterator;
    io_object_t   device;
    
    CFMutableDictionaryRef matchingDictionary = IOServiceMatching("AppleSMC");
    result = IOServiceGetMatchingServices(kIOMasterPortDefault, matchingDictionary, &iterator);
    if (result != kIOReturnSuccess)
    {
        printf("Error: IOServiceGetMatchingServices() = %08x\n", result);
        return 1;
    }
    
    device = IOIteratorNext(iterator);
    IOObjectRelease(iterator);
    if (device == 0)
    {
        printf("Error: no SMC found\n");
        return 1;
    }
    
    result = IOServiceOpen(device, mach_task_self(), 0, &conn);
    IOObjectRelease(device);
    if (result != kIOReturnSuccess)
    {
        printf("Error: IOServiceOpen() = %08x\n", result);
        return 1;
    }
    
    return kIOReturnSuccess;
}

kern_return_t SMCClose()
{
    return IOServiceClose(conn);
}


kern_return_t SMCCall(int index, SMCKeyData_t *inputStructure, SMCKeyData_t *outputStructure)
{
    size_t   structureInputSize;
    size_t   structureOutputSize;
    
    structureInputSize = sizeof(SMCKeyData_t);
    structureOutputSize = sizeof(SMCKeyData_t);
    
#if MAC_OS_X_VERSION_10_5
    return IOConnectCallStructMethod( conn, index,
                                     // inputStructure
                                     inputStructure, structureInputSize,
                                     // ouputStructure
                                     outputStructure, &structureOutputSize );
#else
    return IOConnectMethodStructureIStructureO( conn, index,
                                               structureInputSize, /* structureInputSize */
                                               &structureOutputSize,   /* structureOutputSize */
                                               inputStructure,        /* inputStructure */
                                               outputStructure);       /* ouputStructure */
#endif
    
}

kern_return_t SMCReadKey(UInt32Char_t key, SMCVal_t *val)
{
    kern_return_t result;
    SMCKeyData_t  inputStructure;
    SMCKeyData_t  outputStructure;
    
    memset(&inputStructure, 0, sizeof(SMCKeyData_t));
    memset(&outputStructure, 0, sizeof(SMCKeyData_t));
    memset(val, 0, sizeof(SMCVal_t));
    
    inputStructure.key = _strtoul(key, 4, 16);
    inputStructure.data8 = SMC_CMD_READ_KEYINFO;
    
    result = SMCCall(KERNEL_INDEX_SMC, &inputStructure, &outputStructure);
    if (result != kIOReturnSuccess)
        return result;
    
    val->dataSize = outputStructure.keyInfo.dataSize;
    _ultostr(val->dataType, outputStructure.keyInfo.dataType);
    inputStructure.keyInfo.dataSize = val->dataSize;
    inputStructure.data8 = SMC_CMD_READ_BYTES;
    
    result = SMCCall(KERNEL_INDEX_SMC, &inputStructure, &outputStructure);
    if (result != kIOReturnSuccess)
        return result;
    
    memcpy(val->bytes, outputStructure.bytes, sizeof(outputStructure.bytes));
    
    return kIOReturnSuccess;
}

double SMCGetTemperature(char *key)
{
    SMCVal_t val;
    kern_return_t result;
    
    result = SMCReadKey(key, &val);
    if (result == kIOReturnSuccess) {
        // read succeeded - check returned value
        if (val.dataSize > 0) {
            if (strcmp(val.dataType, DATATYPE_SP78) == 0) {
                // convert sp78 value to temperature
                int intValue = val.bytes[0] * 256 + (unsigned char)val.bytes[1];
                return intValue / 256.0;
            }
        }
    }
    // read failed
    return 0.0;
}

double convertToFahrenheit(double celsius) {
    return (celsius * (9.0 / 5.0)) + 32.0;
}

static char scale = 'C';
static unsigned int poke_time = 8;

@interface AppDelegate ()

@property (strong, nonatomic) NSStatusItem *statusItem;
@property (strong, nonatomic) NSMenu *statusMenu;

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    [self.statusItem setMenu:self.statusMenu];
    [self.statusItem setTitle:@"?.?%C"];
    [self.statusItem setHighlightMode:YES];
    
    self.statusMenu = [[NSMenu alloc] init];
    [self.statusMenu addItemWithTitle:@"C or F?" action:@selector(null) keyEquivalent:@""];
    [self.statusMenu addItem:[NSMenuItem separatorItem]]; // A thin grey line
    [self.statusMenu addItemWithTitle:@"Quit?" action:@selector(terminate:) keyEquivalent:@""];
    self.statusItem.menu = self.statusMenu;
    
    NSOperationQueue *myQueue = [[NSOperationQueue alloc] init];
    /*id myBackgroundActivity = [[NSProcessInfo processInfo]
                               beginActivityWithOptions: NSActivityBackground
                               reason: @"Get CPU Temperature"];*/
    [myQueue addOperationWithBlock:^{
        // Do important background work here
        while (1) {
            SMCOpen();
            double temperature = SMCGetTemperature(SMC_KEY_CPU_TEMP);
            SMCClose();
            
            if (scale == 'F') {
                temperature = convertToFahrenheit(temperature);
            }
            
            //printf("%0.1f°%c\n", temperature, scale);
            
            NSString* oc_temp = [NSString stringWithFormat:@"%0.1f°%c" , temperature, scale];
            [self.statusItem setTitle:oc_temp];
            sleep(poke_time);
            //[[NSProcessInfo processInfo] endActivity:myBackgroundActivity];
        }
    }];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}




@end
