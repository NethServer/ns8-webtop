"""Phone profiles: the headers and behavior of real clients."""

PROFILES = {
    "davx5": {
        "protocol": "dav",
        "user_agent": "DAVx5/4.4.3.2-ose (2024/09/27; dav4jvm; okhttp/4.12.0) Android/14",
        "strategy": "sync-collection",
    },
    "ios-dav": {
        "protocol": "dav",
        "user_agent": "iOS/17.6.1 (21G93) dataaccessd/1.0",
        "strategy": "ctag",
    },
    "ios-eas": {
        "protocol": "eas",
        "user_agent": "Apple-iPhone15C2/2107.93",
        "device_type": "iPhone",
        "device_id": "e2eiphone0000001",
        "max_protocol": "16.1",
    },
    "android-eas": {
        "protocol": "eas",
        "user_agent": "Android-Mail/2024.09.08.672383104.Release",
        "device_type": "Android",
        "device_id": "e2eandroid000001",
        "max_protocol": "14.1",
    },
}
