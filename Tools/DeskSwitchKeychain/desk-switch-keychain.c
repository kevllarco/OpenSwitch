// Read the one OpenSwitch pairing key for the signed parent app only.
// No arguments, persistent service, network access, or general keychain access.
#include <CoreFoundation/CoreFoundation.h>
#include <Security/Security.h>
#include <unistd.h>
#include <stdlib.h>

#ifndef OPENSWITCH_BUNDLE_ID
#define OPENSWITCH_BUNDLE_ID "dev.opendisplay.app"
#endif
#define PEER_SERVICE OPENSWITCH_BUNDLE_ID ".peer-key"

static CFDataRef signing_certificate(SecCodeRef code) {
    CFDictionaryRef info = NULL;
    if (SecCodeCheckValidity(code, kSecCSStrictValidate, NULL) != errSecSuccess ||
        SecCodeCopySigningInformation(code, kSecCSSigningInformation, &info) != errSecSuccess) return NULL;
    CFArrayRef certificates = CFDictionaryGetValue(info, kSecCodeInfoCertificates);
    CFDataRef data = NULL;
    if (certificates && CFArrayGetCount(certificates) > 0) {
        SecCertificateRef cert = (SecCertificateRef)CFArrayGetValueAtIndex(certificates, 0);
        data = SecCertificateCopyData(cert);
    }
    CFRelease(info);
    return data;
}

static int authorized_parent(void) {
    int ok = 0;
    pid_t pid = getppid();
    CFNumberRef number = CFNumberCreate(NULL, kCFNumberIntType, &pid);
    const void *keys[] = { kSecGuestAttributePid };
    const void *values[] = { number };
    CFDictionaryRef attributes = CFDictionaryCreate(NULL, keys, values, 1,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    SecCodeRef parent = NULL, self = NULL;
    CFDictionaryRef info = NULL;
    CFDataRef parentCert = NULL, selfCert = NULL;
    if (SecCodeCopyGuestWithAttributes(NULL, attributes, kSecCSDefaultFlags, &parent) != errSecSuccess ||
        SecCodeCopySelf(kSecCSDefaultFlags, &self) != errSecSuccess ||
        SecCodeCopySigningInformation(parent, kSecCSSigningInformation, &info) != errSecSuccess) goto done;
    CFStringRef identifier = CFDictionaryGetValue(info, kSecCodeInfoIdentifier);
    if (!identifier || !CFEqual(identifier, CFSTR(OPENSWITCH_BUNDLE_ID))) goto done;
    parentCert = signing_certificate(parent);
    selfCert = signing_certificate(self);
    ok = parentCert && selfCert && CFEqual(parentCert, selfCert);
 done:
    if (parentCert) CFRelease(parentCert);
    if (selfCert) CFRelease(selfCert);
    if (info) CFRelease(info);
    if (parent) CFRelease(parent);
    if (self) CFRelease(self);
    CFRelease(attributes); CFRelease(number);
    return ok;
}

int main(int argc, char **argv) {
    (void)argv;
    if (argc != 1 || !authorized_parent()) return 77;
    const void *keys[] = {kSecClass, kSecAttrService, kSecAttrAccount, kSecReturnData, kSecMatchLimit};
    const void *values[] = {kSecClassGenericPassword, CFSTR(PEER_SERVICE),
        CFSTR("local-network-pairing"), kCFBooleanTrue, kSecMatchLimitOne};
    CFDictionaryRef query = CFDictionaryCreate(NULL, keys, values, 5,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching(query, &result);
    CFRelease(query);
    if (status != errSecSuccess || !result || CFGetTypeID(result) != CFDataGetTypeID() ||
        CFDataGetLength((CFDataRef)result) != 32) {
        if (result) CFRelease(result);
        return status == errSecItemNotFound ? 3 : 2;
    }
    const UInt8 *bytes = CFDataGetBytePtr((CFDataRef)result);
    size_t written = 0;
    while (written < 32) {
        ssize_t n = write(STDOUT_FILENO, bytes + written, 32 - written);
        if (n <= 0) { CFRelease(result); return 1; }
        written += (size_t)n;
    }
    CFRelease(result);
    return 0;
}
