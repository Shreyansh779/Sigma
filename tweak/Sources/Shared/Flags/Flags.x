// Spotify reads every remote-config flag once at startup through the configuration provider,
// keyed "component.property". The value handed back is Core/SGFlagForce.h's: what the redesign forces
// (Redesigned/Kit/SGRedesign.h), which comes before an override so one left from Spotify's own screens
// cannot pull a redesigned one apart, then an override from the Flags page, then what the Search switches
// and the lyrics sources force.
#import "Core/SGCore.h"
#import "Flags.h"

static id forced(NSString *key) {
    return SGForcedFlagValue(key);
}

static BOOL boolFor(NSString *key, BOOL orig) {
    id value = forced(key);
    return value ? [value boolValue] : orig;
}

static long intFor(NSString *key, long lower, long upper, long orig) {
    id value = forced(key);
    return value ? MAX(lower, MIN(upper, (long)[value longLongValue])) : orig;
}

// 9.1.88's switch over the system's own glass (default, force_enabled, force_disabled). Default leaves it
// to Info.plist, where the IPA build turns glass on; a force_disabled from Spotify's servers would take
// the glass off the redesign's bars. 9.1.90's own Liquid Glass tab bar is off by default, and both looks
// build on the tab bar as it is, so a server turning it on would pull them apart. Both pinned in both
// looks, after an override from the All flags page; neither key exists in 9.1.78, so nothing asks.
static NSString *const kGlassOverride = @"ios-reprise-liquid-glass-override.mode";
static NSString *const kGlassTabBar = @"ios-navigationui-tabbar-impl.is_liquid_glass_tab_bar_enabled";

static id enumFor(NSString *key, id orig) {
    id value = forced(key);
    return [value isKindOfClass:NSString.class] ? value : orig;
}

%hook _TtC22RemoteConfigurationSDK25ConfigurationProviderImpl
- (BOOL)boolValueForId:(NSString *)key defaultValue:(BOOL)fallback {
    BOOL orig = %orig;
    return boolFor(key, orig);
}
- (long)intValueForId:(NSString *)key lower:(long)lower upper:(long)upper defaultValue:(long)fallback {
    long orig = %orig;
    return intFor(key, lower, upper, orig);
}
- (id)enumValueForId:(NSString *)key values:(NSArray *)values defaultValue:(id)fallback {
    id orig = %orig;
    return enumFor(key, orig);
}
%end

// The observable properties listed in Info.plist go through a second provider.
%hook _TtC22RemoteConfigurationSDK35ObservableConfigurationProviderImpl
- (BOOL)boolValueForId:(NSString *)key defaultValue:(BOOL)fallback {
    BOOL orig = %orig;
    return boolFor(key, orig);
}
- (long)intValueForId:(NSString *)key lower:(long)lower upper:(long)upper defaultValue:(long)fallback {
    long orig = %orig;
    return intFor(key, lower, upper, orig);
}
- (id)enumValueForId:(NSString *)key values:(NSArray *)values defaultValue:(id)fallback {
    id orig = %orig;
    return enumFor(key, orig);
}
%end

%ctor {
    SGRegisterFlagForcer(NO, ^id(NSString *key) {
        if ([key isEqualToString:kGlassOverride]) return @"default";
        return [key isEqualToString:kGlassTabBar] ? @NO : nil;
    }, nil);
    %init;
    SGRequireClasses(@[
        @"_TtC22RemoteConfigurationSDK25ConfigurationProviderImpl",
        @"_TtC22RemoteConfigurationSDK35ObservableConfigurationProviderImpl",
    ]);
}
