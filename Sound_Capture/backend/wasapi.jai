capture_init :: () {
    CoInitialize(null);

    CLSID_MMDeviceEnumerator := *uid("BCDE0395-E52F-467C-8E3D-C4579291692E");
    hr := CoCreateInstance(CLSID_MMDeviceEnumerator, null, CLSCTX_ALL, *uid(IMMDeviceEnumerator_UUID), cast(**void)*enumerator);
    check_hr("CoCreateInstance");

    refresh_capture_devices();
    default_device := get_default_capture_device();
    set_capture_device(default_device);
}

start_recording :: () {
    hr := IAudioClient_Start(client);
    check_hr("Client start");
}

stop_recording :: () {
    hr := IAudioClient_Stop(client);
    check_hr("Client stop");
}

capture_deinit :: () {
    for * sound_capture_devices {
        free_device(it);
    }

    array_reset(*sound_capture_devices);

    safe_release_and_reset(*enumerator);
    safe_release_and_reset(*client);
    safe_release_and_reset(*capture_client);

    CoUninitialize();
}

// Allocated with temp
get_next_sound_buffer :: () -> []s16 {
    packet_length: u32;
    hr := IAudioCaptureClient_GetNextPacketSize(capture_client, *packet_length);

    if !check_hr("Get next packet size") {
        return .[];
    }

    buffer := [..]s16.{ allocator=temp };
    while packet_length != 0 {
        num_frames: u32;
        data: []s16;

        flags: u32;

        DATA_DISCONTINUITY :: 1;
        SILENT             :: 2;
        TIMESTAMP_ERROR    :: 4;

        hr := IAudioCaptureClient_GetBuffer(capture_client, cast(**u8)*data.data, *num_frames, *flags, null, null);
        data.count = num_frames * NUM_CHANNELS;
        if check_hr("Get buffer") && !(flags & SILENT) {
            array_add(*buffer, ..data);
        }

        hr = IAudioCaptureClient_ReleaseBuffer(capture_client, num_frames);
        check_hr("Release buffer");

        hr = IAudioCaptureClient_GetNextPacketSize(capture_client, *packet_length);
        check_hr("Get next packet size");
    }

    return buffer;
}

refresh_capture_devices :: () {
    for * sound_capture_devices {
        free_device(it);
    }
    array_reset(*sound_capture_devices);

    collection: *IMMDeviceCollection;

    hr := IMMDeviceEnumerator_EnumAudioEndpoints(enumerator, .eCapture, DEVICE_STATE_ACTIVE, *collection);
    check_hr("Enum audio endpoints");

    count: u32;
    IMMDeviceCollection_GetCount(collection, *count);

    array_resize(*sound_capture_devices, count);

    for 0..count-1 {
        imm_device: *IMMDevice;
        hr = IMMDeviceCollection_Item(collection, it, *imm_device);
        check_hr("Collection item");
        fill_device(*sound_capture_devices[it], imm_device);
    }
    safe_release(collection);

    #import "Windows_Utf8";
}

get_default_capture_device :: () -> *Input_Device {
    imm_device: *IMMDevice;
    hr := IMMDeviceEnumerator_GetDefaultAudioEndpoint(enumerator, .eCapture, .eConsole, *imm_device);
    check_hr("Get audio endpoint");

    id: *u16;
    hr = IMMDevice_GetId(imm_device, *id);
    check_hr("Device get id");

    for * d: sound_capture_devices {
        // Check if the ids are the same.
        index := 0;
        while true {
            id0, id1 := id[index], (cast(*u16)d.internal_id)[index];
            if id0 == 0 && id1 == 0 {
                IUnknown_Release(imm_device);
                CoTaskMemFree(id);
                return d;
            }
            else if id0 != id1 continue d;
            index += 1;
        }
    }

    // We plugged something while we were checking... or something.
    // You have to refresh the devices in this case.
    return null;
}

set_capture_device :: (device: *Input_Device) {
    if client {
        stop_recording();
        IUnknown_Release(client);
    }
    safe_release(capture_client);

    imm_device := cast(*IMMDevice)device.internal_data;

    // mix_format: *Waveformatex;
    // hr = IAudioClient_GetMixFormat(client, *mix_format);
    // check_hr("Get mix format");

    mix_format: = Waveformatex.{
        nChannels = NUM_CHANNELS,
        nSamplesPerSec = SAMPLE_RATE,
        nAvgBytesPerSec = SAMPLE_RATE * BLOCK_ALIGN,
        nBlockAlign = BLOCK_ALIGN,
        wBitsPerSample = BIT_DEPTH,
        wFormatTag = WAVE_FORMAT_PCM,
    };

    hr := IMMDevice_Activate(imm_device, *uid(IAudioClient3_UUID), CLSCTX_ALL, null, cast(**void)*client);
    check_hr("Device activate");


    properties := AudioClientProperties.{
        cbSize = size_of(AudioClientProperties),
        Options = .RAW,
    };

    hr = IAudioClient2_SetClientProperties(client, *properties);
    check_hr("Set client properties");

    hr = IAudioClient3_InitializeSharedAudioStream(client, 0, 0, *mix_format, null);
    check_hr("Client initialize");

    hr = IAudioClient_GetService(client, *uid(IAudioCaptureClient_UUID), cast(**void)*capture_client);
    check_hr("Client get service");

}

free_device :: (device: *Input_Device) {
    if device.name free(device.name);
    if device.internal_id CoTaskMemFree(device.internal_id);
    safe_release(cast(*IMMDevice)device.internal_data);

    device.* = .{};
}

#scope_file

fill_device :: (device: *Input_Device, imm_device: *IMMDevice) {
    property_store: *IPropertyStore;
    defer safe_release(property_store);
    device.internal_data = imm_device;

    hr := IMMDevice_GetId(imm_device, cast(**u16)*device.internal_id);
    check_hr("Device get id");

    hr = IMMDevice_OpenPropertyStore(imm_device, STGM_READ, *property_store);
    check_hr("Device open property store");

    var_name: PROPVARIANT;
    hr = IPropertyStore_GetValue(property_store, *PKEY_Device_FriendlyName, *var_name);
    check_hr("Property store get value");

    device.name = wide_to_utf8(var_name.pwszVal);
    PropVariantClear(*var_name);
}


// COM stuff
CLSCTX_INPROC_SERVER    :: 0x1;
CLSCTX_INPROC_HANDLER   :: 0x2;
CLSCTX_LOCAL_SERVER     :: 0x4;
CLSCTX_REMOTE_SERVER    :: 0x10;

CLSCTX_ALL   :: CLSCTX_INPROC_SERVER|CLSCTX_INPROC_HANDLER|CLSCTX_LOCAL_SERVER|CLSCTX_REMOTE_SERVER;

CoInitialize   :: (pvReserved: *void) -> HRESULT #foreign Ole32;
CoUninitialize :: () -> void    #foreign Ole32;

REFCLSID :: *IID;

CoCreateInstance :: (rclsid: REFCLSID, pUnkOuter: *IUnknown, dwClsContext: u32, riid: REFIID, ppv: **void) -> HRESULT #foreign Ole32;

CoTaskMemFree :: (pointer: *void) #foreign Ole32;

Ole32 :: #system_library "ole32";

//
// WASAPI Bindings
//

DEVICE_STATE_ACTIVE     :: 0x1;
DEVICE_STATE_DISABLED   :: 0x2;
DEVICE_STATE_NOTPRESENT :: 0x4;
DEVICE_STATE_UNPLUGGED  :: 0x8;
DEVICE_STATEMASK_ALL    :: 0xF;

STGM_READ :: 0;

EDataFlow :: enum s32 {
    eRender              :: 0;
    eCapture             :: 1;
    eAll                 :: 2;
    EDataFlow_enum_count :: 3;
}

ERole :: enum s32 {
    eConsole         :: 0;
    eMultimedia      :: 1;
    eCommunications  :: 2;
    ERole_enum_count :: 3;
}

AUDCLNT_SHAREMODE :: enum s32 {
    SHARED :: 0;
    EXCLUSIVE :: 1;
}

LPCGUID :: *GUID;

AUDCLNT_STREAMOPTIONS :: enum s32 {
  NONE;
  RAW;
  MATCH_FORMAT;
  AMBISONICS;
  POST_VOLUME_LOOPBACK;
}

AUDIO_STREAM_CATEGORY :: enum s32 {
    Other               :: 0;
    ForegroundOnlyMedia :: 1;

    Communications      :: 3;
    Alerts              :: 4;
    SoundEffects        :: 5;
    GameEffects         :: 6;
    GameMedia           :: 7;
    GameChat            :: 8;
    Speech              :: 9;
    Movie               :: 10;
    Media               :: 11;

    FarFieldSpeech      :: 12;
    UniformSpeech       :: 13;
    VoiceTyping         :: 14;
}

AudioClientProperties :: struct {
    cbSize:     u32;
    bIsOffload: BOOL;
    eCategory:  AUDIO_STREAM_CATEGORY;
    Options:    AUDCLNT_STREAMOPTIONS;
}

IAudioClient_UUID :: "1CB9AD4C-DBFA-4c32-B178-C2F568A703B2";
IAudioClient :: struct {
    vtable: *IAudioClient_VTable;
    #place vtable; #as iunknown: IUnknown; // Support cast to IUnknown
}
IAudioClient_VTable :: struct #type_info_none {
    using vtable:      IUnknown_VTable;

    Initialize:        #type (this: *IAudioClient, ShareMode: AUDCLNT_SHAREMODE, StreamFlags: u32, hnsBufferDuration: s64, hnsPeriodicity: s64, pFormat: *Waveformatex, AudioSessionGuid: LPCGUID) -> HRESULT #cpp_method;

    GetBufferSize:     #type (this: *IAudioClient, pNumBufferFrames: *u32) -> HRESULT #cpp_method;

    GetStreamLatency:  #type (this: *IAudioClient, phnsLatency: *s64) -> HRESULT #cpp_method;

    GetCurrentPadding: #type (this: *IAudioClient, pNumPaddingFrames: *u32) -> HRESULT #cpp_method;

    IsFormatSupported: #type (this: *IAudioClient, ShareMode: AUDCLNT_SHAREMODE, pFormat: *Waveformatex, ppClosestMatch: **Waveformatex) -> HRESULT #cpp_method;

    GetMixFormat:      #type (this: *IAudioClient, ppDeviceFormat: **Waveformatex) -> HRESULT #cpp_method;

    GetDevicePeriod:   #type (this: *IAudioClient, phnsDefaultDevicePeriod: *s64, phnsMinimumDevicePeriod: *s64) -> HRESULT #cpp_method;

    Start:             #type (this: *IAudioClient) -> HRESULT #cpp_method;

    Stop:              #type (this: *IAudioClient) -> HRESULT #cpp_method;

    Reset:             #type (this: *IAudioClient) -> HRESULT #cpp_method;

    SetEventHandle:    #type (this: *IAudioClient, eventHandle: HANDLE) -> HRESULT #cpp_method;

    GetService:        #type (this: *IAudioClient, riid: *IID, ppv: **void) -> HRESULT #cpp_method;
}
IAudioClient_Initialize :: inline (this: *IAudioClient, ShareMode: AUDCLNT_SHAREMODE, StreamFlags: u32, hnsBufferDuration: s64, hnsPeriodicity: s64, pFormat: *Waveformatex, AudioSessionGuid: LPCGUID) -> HRESULT { return this.vtable.Initialize(this, ShareMode, StreamFlags, hnsBufferDuration, hnsPeriodicity, pFormat, AudioSessionGuid); }

IAudioClient_GetBufferSize :: inline (this: *IAudioClient, pNumBufferFrames: *u32) -> HRESULT { return this.vtable.GetBufferSize(this, pNumBufferFrames); }

IAudioClient_GetStreamLatency :: inline (this: *IAudioClient, phnsLatency: *s64) -> HRESULT { return this.vtable.GetStreamLatency(this, phnsLatency); }

IAudioClient_GetCurrentPadding :: inline (this: *IAudioClient, pNumPaddingFrames: *u32) -> HRESULT { return this.vtable.GetCurrentPadding(this, pNumPaddingFrames); }

IAudioClient_IsFormatSupported :: inline (this: *IAudioClient, ShareMode: AUDCLNT_SHAREMODE, pFormat: *Waveformatex, ppClosestMatch: **Waveformatex) -> HRESULT { return this.vtable.IsFormatSupported(this, ShareMode, pFormat, ppClosestMatch); }

IAudioClient_GetMixFormat :: inline (this: *IAudioClient, ppDeviceFormat: **Waveformatex) -> HRESULT { return this.vtable.GetMixFormat(this, ppDeviceFormat); }

IAudioClient_GetDevicePeriod :: inline (this: *IAudioClient, phnsDefaultDevicePeriod: *s64, phnsMinimumDevicePeriod: *s64) -> HRESULT { return this.vtable.GetDevicePeriod(this, phnsDefaultDevicePeriod, phnsMinimumDevicePeriod); }

IAudioClient_Start :: inline (this: *IAudioClient) -> HRESULT { return this.vtable.Start(this); }

IAudioClient_Stop :: inline (this: *IAudioClient) -> HRESULT { return this.vtable.Stop(this); }

IAudioClient_Reset :: inline (this: *IAudioClient) -> HRESULT { return this.vtable.Reset(this); }

IAudioClient_SetEventHandle :: inline (this: *IAudioClient, eventHandle: HANDLE) -> HRESULT { return this.vtable.SetEventHandle(this, eventHandle); }

IAudioClient_GetService :: inline (this: *IAudioClient, riid: *IID, ppv: **void) -> HRESULT { return this.vtable.GetService(this, riid, ppv); }

vtable :: (obj: *IAudioClient) -> *IAudioClient_VTable { return obj.vtable; }

IAudioClient2_UUID :: "726778CD-F60A-4eda-82DE-E47610CD78AA";
IAudioClient2 :: struct {
    vtable: *IAudioClient2_VTable;
    #place vtable; #as iaudioclient: IAudioClient; // Support cast to IAudioClient
}
IAudioClient2_VTable :: struct #type_info_none {
    using,except(vtable) vtable:              IAudioClient_VTable;

    IsOffloadCapable:    #type (this: *IAudioClient2, Category: u32, pbOffloadCapable: *BOOL) -> HRESULT #cpp_method;

    SetClientProperties: #type (this: *IAudioClient2, pProperties: *AudioClientProperties) -> HRESULT #cpp_method;

    GetBufferSizeLimits: #type (this: *IAudioClient2, pFormat: *Waveformatex, bEventDriven: BOOL, phnsMinBufferDuration: *s64, phnsMaxBufferDuration: *s64) -> HRESULT #cpp_method;
}
IAudioClient2_IsOffloadCapable :: inline (this: *IAudioClient2, Category: u32, pbOffloadCapable: *BOOL) -> HRESULT { return this.vtable.IsOffloadCapable(this, Category, pbOffloadCapable); }

IAudioClient2_SetClientProperties :: inline (this: *IAudioClient2, pProperties: *AudioClientProperties) -> HRESULT { return this.vtable.SetClientProperties(this, pProperties); }

IAudioClient2_GetBufferSizeLimits :: inline (this: *IAudioClient2, pFormat: *Waveformatex, bEventDriven: BOOL, phnsMinBufferDuration: *s64, phnsMaxBufferDuration: *s64) -> HRESULT { return this.vtable.GetBufferSizeLimits(this, pFormat, bEventDriven, phnsMinBufferDuration, phnsMaxBufferDuration); }

vtable :: (obj: *IAudioClient2) -> *IAudioClient2_VTable { return obj.vtable; }

IAudioClient3_UUID :: "7ED4EE07-8E67-4CD4-8C1A-2B7A5987AD42";
IAudioClient3 :: struct {
    vtable: *IAudioClient3_VTable;
    #place vtable; #as iaudioclient2: IAudioClient2; // Support cast to IAudioClient2
}
IAudioClient3_VTable :: struct #type_info_none {
    using,except(vtable) vtable:                           IAudioClient2_VTable;

    GetSharedModeEnginePeriod:        #type (this: *IAudioClient3, pFormat: *Waveformatex, pDefaultPeriodInFrames: *u32, pFundamentalPeriodInFrames: *u32, pMinPeriodInFrames: *u32, pMaxPeriodInFrames: *u32) -> HRESULT #cpp_method;

    GetCurrentSharedModeEnginePeriod: #type (this: *IAudioClient3, ppFormat: **Waveformatex, pCurrentPeriodInFrames: *u32) -> HRESULT #cpp_method;

    InitializeSharedAudioStream:      #type (this: *IAudioClient3, StreamFlags: u32, PeriodInFrames: u32, pFormat: *Waveformatex, AudioSessionGuid: LPCGUID) -> HRESULT #cpp_method;
}
IAudioClient3_GetSharedModeEnginePeriod :: inline (this: *IAudioClient3, pFormat: *Waveformatex, pDefaultPeriodInFrames: *u32, pFundamentalPeriodInFrames: *u32, pMinPeriodInFrames: *u32, pMaxPeriodInFrames: *u32) -> HRESULT { return this.vtable.GetSharedModeEnginePeriod(this, pFormat, pDefaultPeriodInFrames, pFundamentalPeriodInFrames, pMinPeriodInFrames, pMaxPeriodInFrames); }

IAudioClient3_GetCurrentSharedModeEnginePeriod :: inline (this: *IAudioClient3, ppFormat: **Waveformatex, pCurrentPeriodInFrames: *u32) -> HRESULT { return this.vtable.GetCurrentSharedModeEnginePeriod(this, ppFormat, pCurrentPeriodInFrames); }

IAudioClient3_InitializeSharedAudioStream :: inline (this: *IAudioClient3, StreamFlags: u32, PeriodInFrames: u32, pFormat: *Waveformatex, AudioSessionGuid: LPCGUID) -> HRESULT { return this.vtable.InitializeSharedAudioStream(this, StreamFlags, PeriodInFrames, pFormat, AudioSessionGuid); }

vtable :: (obj: *IAudioClient3) -> *IAudioClient3_VTable { return obj.vtable; }


IAudioCaptureClient_UUID :: "C8ADBD64-E71E-48a0-A4DE-185C395CD317";
IAudioCaptureClient :: struct {
    vtable: *IAudioCaptureClient_VTable;
    #place vtable; #as iunknown: IUnknown; // Support cast to IUnknown
}
IAudioCaptureClient_VTable :: struct #type_info_none {
    using vtable:      IUnknown_VTable;

    GetBuffer:         #type (this: *IAudioCaptureClient, ppData: **u8, pNumFramesToRead: *u32, pdwFlags: *u32, pu64DevicePosition: *u64, pu64QPCPosition: *u64) -> HRESULT #cpp_method;

    ReleaseBuffer:     #type (this: *IAudioCaptureClient, NumFramesRead: u32) -> HRESULT #cpp_method;

    GetNextPacketSize: #type (this: *IAudioCaptureClient, pNumFramesInNextPacket: *u32) -> HRESULT #cpp_method;
}
IAudioCaptureClient_GetBuffer :: inline (this: *IAudioCaptureClient, ppData: **u8, pNumFramesToRead: *u32, pdwFlags: *u32, pu64DevicePosition: *u64, pu64QPCPosition: *u64) -> HRESULT { return this.vtable.GetBuffer(this, ppData, pNumFramesToRead, pdwFlags, pu64DevicePosition, pu64QPCPosition); }

IAudioCaptureClient_ReleaseBuffer :: inline (this: *IAudioCaptureClient, NumFramesRead: u32) -> HRESULT { return this.vtable.ReleaseBuffer(this, NumFramesRead); }

IAudioCaptureClient_GetNextPacketSize :: inline (this: *IAudioCaptureClient, pNumFramesInNextPacket: *u32) -> HRESULT { return this.vtable.GetNextPacketSize(this, pNumFramesInNextPacket); }

vtable :: (obj: *IAudioCaptureClient) -> *IAudioCaptureClient_VTable { return obj.vtable; }


IMMDevice_UUID :: "D666063F-1587-4E43-81F1-B948E807363F";
IMMDevice :: struct {
    vtable: *IMMDevice_VTable;
    #place vtable; #as iunknown: IUnknown; // Support cast to IUnknown
}
IMMDevice_VTable :: struct #type_info_none {
    using vtable:      IUnknown_VTable;

    Activate:          #type (this: *IMMDevice, iid: *IID, dwClsCtx: u32, pActivationParams: *void, ppInterface: **void) -> HRESULT #cpp_method;

    OpenPropertyStore: #type (this: *IMMDevice, stgmAccess: u32, ppProperties: **IPropertyStore) -> HRESULT #cpp_method;

    GetId:             #type (this: *IMMDevice, ppstrId: **u16) -> HRESULT #cpp_method;

    GetState:          #type (this: *IMMDevice, pdwState: *u32) -> HRESULT #cpp_method;
}
IMMDevice_Activate :: inline (this: *IMMDevice, iid: *IID, dwClsCtx: u32, pActivationParams: *void, ppInterface: **void) -> HRESULT { return this.vtable.Activate(this, iid, dwClsCtx, pActivationParams, ppInterface); }

IMMDevice_OpenPropertyStore :: inline (this: *IMMDevice, stgmAccess: u32, ppProperties: **IPropertyStore) -> HRESULT { return this.vtable.OpenPropertyStore(this, stgmAccess, ppProperties); }

IMMDevice_GetId :: inline (this: *IMMDevice, ppstrId: **u16) -> HRESULT { return this.vtable.GetId(this, ppstrId); }

IMMDevice_GetState :: inline (this: *IMMDevice, pdwState: *u32) -> HRESULT { return this.vtable.GetState(this, pdwState); }

vtable :: (obj: *IMMDevice) -> *IMMDevice_VTable { return obj.vtable; }

IMMDeviceEnumerator_UUID :: "A95664D2-9614-4F35-A746-DE8DB63617E6";
IMMDeviceEnumerator :: struct {
    vtable: *IMMDeviceEnumerator_VTable;
    #place vtable; #as iunknown: IUnknown; // Support cast to IUnknown
}
IMMDeviceEnumerator_VTable :: struct #type_info_none {
    using vtable:                           IUnknown_VTable;

    EnumAudioEndpoints:                     #type (this: *IMMDeviceEnumerator, dataFlow: EDataFlow, dwStateMask: u32, ppDevices: **IMMDeviceCollection) -> HRESULT #cpp_method;

    GetDefaultAudioEndpoint:                #type (this: *IMMDeviceEnumerator, dataFlow: EDataFlow, role: ERole, ppEndpoint: **IMMDevice) -> HRESULT #cpp_method;

    GetDevice:                              #type (this: *IMMDeviceEnumerator, pwstrId: *s16, ppDevice: **IMMDevice) -> HRESULT #cpp_method;

    RegisterEndpointNotificationCallback:   #type (this: *IMMDeviceEnumerator, pClient: *IMMNotificationClient) -> HRESULT #cpp_method;

    UnregisterEndpointNotificationCallback: #type (this: *IMMDeviceEnumerator, pClient: *IMMNotificationClient) -> HRESULT #cpp_method;
}
IMMDeviceEnumerator_EnumAudioEndpoints :: inline (this: *IMMDeviceEnumerator, dataFlow: EDataFlow, dwStateMask: u32, ppDevices: **IMMDeviceCollection) -> HRESULT { return this.vtable.EnumAudioEndpoints(this, dataFlow, dwStateMask, ppDevices); }

IMMDeviceEnumerator_GetDefaultAudioEndpoint :: inline (this: *IMMDeviceEnumerator, dataFlow: EDataFlow, role: ERole, ppEndpoint: **IMMDevice) -> HRESULT { return this.vtable.GetDefaultAudioEndpoint(this, dataFlow, role, ppEndpoint); }

IMMDeviceEnumerator_GetDevice :: inline (this: *IMMDeviceEnumerator, pwstrId: *s16, ppDevice: **IMMDevice) -> HRESULT { return this.vtable.GetDevice(this, pwstrId, ppDevice); }

IMMDeviceEnumerator_RegisterEndpointNotificationCallback :: inline (this: *IMMDeviceEnumerator, pClient: *IMMNotificationClient) -> HRESULT { return this.vtable.RegisterEndpointNotificationCallback(this, pClient); }

IMMDeviceEnumerator_UnregisterEndpointNotificationCallback :: inline (this: *IMMDeviceEnumerator, pClient: *IMMNotificationClient) -> HRESULT { return this.vtable.UnregisterEndpointNotificationCallback(this, pClient); }

vtable :: (obj: *IMMDeviceEnumerator) -> *IMMDeviceEnumerator_VTable { return obj.vtable; }


IMMDeviceCollection_UUID :: "0BD7A1BE-7A1A-44DB-8397-CC5392387B5E";
IMMDeviceCollection :: struct {
    vtable: *IMMDeviceCollection_VTable;
    #place vtable; #as iunknown: IUnknown; // Support cast to IUnknown
}
IMMDeviceCollection_VTable :: struct #type_info_none {
    using vtable: IUnknown_VTable;

    GetCount:     #type (this: *IMMDeviceCollection, pcDevices: *u32) -> HRESULT #cpp_method;

    Item:         #type (this: *IMMDeviceCollection, nDevice: u32, ppDevice: **IMMDevice) -> HRESULT #cpp_method;
}
IMMDeviceCollection_GetCount :: inline (this: *IMMDeviceCollection, pcDevices: *u32) -> HRESULT { return this.vtable.GetCount(this, pcDevices); }

IMMDeviceCollection_Item :: inline (this: *IMMDeviceCollection, nDevice: u32, ppDevice: **IMMDevice) -> HRESULT { return this.vtable.Item(this, nDevice, ppDevice); }

vtable :: (obj: *IMMDeviceCollection) -> *IMMDeviceCollection_VTable { return obj.vtable; }

PROPERTYKEY :: struct {
    fmtid: GUID;
    pid:   u32;
}
PKEY_Device_FriendlyName :: PROPERTYKEY.{.{0xa45c254e, 0xdf1c, 0x4efd, .[0x80, 0x20, 0x67, 0xd1, 0x46, 0xa8, 0x50, 0xe0]}, 14};
BSTR :: *u16;


PROPVARIANT :: struct {
    vt: u16;
    wReserved: [3]u16;
    union {
        some_member_we_dont_care: [2]u64; // This size is right hopefully
        pwszVal: *u16;
    }
}
PropVariantClear :: (pvar: *PROPVARIANT) -> HRESULT #foreign Ole32;

IPropertyStore :: struct {
    vtable: *IPropertyStore_VTable;
    #place vtable; #as iunknown: IUnknown; // Support cast to IUnknown
}
IPropertyStore_VTable :: struct #type_info_none {
    using vtable: IUnknown_VTable;

    GetCount:     #type (this: *IPropertyStore, cProps: *u32) -> HRESULT #cpp_method;

    GetAt:        #type (this: *IPropertyStore, iProp: u32, pkey: *PROPERTYKEY) -> HRESULT #cpp_method;

    GetValue:     #type (this: *IPropertyStore, key: *PROPERTYKEY, pv: *PROPVARIANT) -> HRESULT #cpp_method;

    SetValue:     #type (this: *IPropertyStore, key: *PROPERTYKEY, propvar: *PROPVARIANT) -> HRESULT #cpp_method;

    Commit:       #type (this: *IPropertyStore) -> HRESULT #cpp_method;
}
IPropertyStore_GetCount :: inline (this: *IPropertyStore, cProps: *u32) -> HRESULT { return this.vtable.GetCount(this, cProps); }

IPropertyStore_GetAt :: inline (this: *IPropertyStore, iProp: u32, pkey: *PROPERTYKEY) -> HRESULT { return this.vtable.GetAt(this, iProp, pkey); }

IPropertyStore_GetValue :: inline (this: *IPropertyStore, key: *PROPERTYKEY, pv: *PROPVARIANT) -> HRESULT { return this.vtable.GetValue(this, key, pv); }

IPropertyStore_SetValue :: inline (this: *IPropertyStore, key: *PROPERTYKEY, propvar: *PROPVARIANT) -> HRESULT { return this.vtable.SetValue(this, key, propvar); }

IPropertyStore_Commit :: inline (this: *IPropertyStore) -> HRESULT { return this.vtable.Commit(this); }

vtable :: (obj: *IPropertyStore) -> *IPropertyStore_VTable { return obj.vtable; }


IMMNotificationClient_UUID :: "7991EEC9-7E89-4D85-8390-6C703CEC60C0";
IMMNotificationClient :: struct {
    vtable: *IMMNotificationClient_VTable;
    #place vtable; #as iunknown: IUnknown; // Support cast to IUnknown
}
IMMNotificationClient_VTable :: struct #type_info_none {
    using vtable:           IUnknown_VTable;

    OnDeviceStateChanged:   #type (this: *IMMNotificationClient, pwstrDeviceId: *s16, dwNewState: u32) -> HRESULT #cpp_method;

    OnDeviceAdded:          #type (this: *IMMNotificationClient, pwstrDeviceId: *s16) -> HRESULT #cpp_method;

    OnDeviceRemoved:        #type (this: *IMMNotificationClient, pwstrDeviceId: *s16) -> HRESULT #cpp_method;

    OnDefaultDeviceChanged: #type (this: *IMMNotificationClient, flow: EDataFlow, role: ERole, pwstrDefaultDeviceId: *s16) -> HRESULT #cpp_method;

    OnPropertyValueChanged: #type (this: *IMMNotificationClient, pwstrDeviceId: *s16, key: s32) -> HRESULT #cpp_method;
}
IMMNotificationClient_OnDeviceStateChanged :: inline (this: *IMMNotificationClient, pwstrDeviceId: *s16, dwNewState: u32) -> HRESULT { return this.vtable.OnDeviceStateChanged(this, pwstrDeviceId, dwNewState); }

IMMNotificationClient_OnDeviceAdded :: inline (this: *IMMNotificationClient, pwstrDeviceId: *s16) -> HRESULT { return this.vtable.OnDeviceAdded(this, pwstrDeviceId); }

IMMNotificationClient_OnDeviceRemoved :: inline (this: *IMMNotificationClient, pwstrDeviceId: *s16) -> HRESULT { return this.vtable.OnDeviceRemoved(this, pwstrDeviceId); }

IMMNotificationClient_OnDefaultDeviceChanged :: inline (this: *IMMNotificationClient, flow: EDataFlow, role: ERole, pwstrDefaultDeviceId: *s16) -> HRESULT { return this.vtable.OnDefaultDeviceChanged(this, flow, role, pwstrDefaultDeviceId); }

IMMNotificationClient_OnPropertyValueChanged :: inline (this: *IMMNotificationClient, pwstrDeviceId: *s16, key: s32) -> HRESULT { return this.vtable.OnPropertyValueChanged(this, pwstrDeviceId, key); }

vtable :: (obj: *IMMNotificationClient) -> *IMMNotificationClient_VTable { return obj.vtable; }

//

#if VERBOSE {
    check_hr :: (name: string) -> bool #expand {
        if FAILED(`hr) {
            System :: #import "System";
            error_code := cast,no_check(OS_Error_Code)`hr; // We know that it is less than 0 if it's a failure. OS_Error_Code is a u32
            fail_message := System.get_error_string(error_code);

            log_error("[sound_capture] % failed with code 0x%: %", name, formatInt(`hr, 16), fail_message);
            return false;
        }
        return true;
    }
}
else {
    check_hr :: (name: string) -> bool #expand {
        return SUCCEEDED(`hr);
    }
}

enumerator: *IMMDeviceEnumerator;
client: *IAudioClient3;
capture_client: *IAudioCaptureClient;

#import "Wav_File";
#import "Windows";
