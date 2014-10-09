//
//  KFTunableSpec.m
//  TunableSpec
//
//  Created by Ken Ferry on 4/29/13.
//  Copyright (c) 2013 Ken Ferry.
//  See LICENSE for details.
//

#import "KFTunableSpec.h"
#import <QuartzCore/QuartzCore.h>
#define stringName(arg) (@""#arg)


static UIImage *CloseImage();
static UIImage *CalloutBezelImage();
static UIImage *CalloutArrowImage();

@interface _KFSpecItem : NSObject {
    NSMapTable *_maintenanceBlocksByOwner;
    id _objectValue;
}
@property (nonatomic) NSString *key;
@property (nonatomic) NSString *label;

@property (nonatomic) id objectValue;
@property (nonatomic) id defaultValue;

- (void)withOwner:(id)weaklyHeldOwner maintain:(void (^)(id owner, id objValue))maintenanceBlock;

// override this
- (UIView *)tuningView;

@end

@implementation _KFSpecItem

+ (NSArray *)propertiesForJSONRepresentation {

    return @[@"key", @"label"];
}

- (id)initWithJSONRepresentation:(NSDictionary *)json {

    if (json[@"key"] == nil) return nil;

    self = [super init];
    if (self) {
        for (NSString *prop in [[self class] propertiesForJSONRepresentation]) {
            [self setValue:json[prop] forKey:prop];
        }

        [self setDefaultValue:[self objectValue]];

        _maintenanceBlocksByOwner = [NSMapTable weakToStrongObjectsMapTable];
        
    }
    return self;
}

- (id)init
{
    NSAssert(0, @"must use initWithJSONRepresentation");
    return self;
}

- (void)withOwner:(id)weaklyHeldOwner maintain:(void (^)(id owner, id objValue))maintenanceBlock {
    NSMutableArray *maintenanceBlocksForOwner = [_maintenanceBlocksByOwner objectForKey:weaklyHeldOwner];
    if (!maintenanceBlocksForOwner) {
        maintenanceBlocksForOwner = [NSMutableArray array];
        [_maintenanceBlocksByOwner setObject:maintenanceBlocksForOwner forKey:weaklyHeldOwner];
    }
    [maintenanceBlocksForOwner addObject:maintenanceBlock];
    maintenanceBlock(weaklyHeldOwner, [self objectValue]);
}

-(id)objectValue {
    return _objectValue;
}

- (void)setObjectValue:(id)objectValue {

    if (![_objectValue isEqual:objectValue]) {
        _objectValue = objectValue;
        objectValue = [self objectValue];
        for (id owner in _maintenanceBlocksByOwner) {
            for (void (^maintenanceBlock)(id owner, id objValue) in [_maintenanceBlocksByOwner objectForKey:owner]) {
                maintenanceBlock(owner, objectValue);
            }
        }
    }
}

static NSString *CamelCaseToSpaces(NSString *camelCaseString) {
    return [camelCaseString stringByReplacingOccurrencesOfString:@"([a-z])([A-Z])" withString:@"$1 $2" options:NSRegularExpressionSearch range:NSMakeRange(0, [camelCaseString length])];

}

- (NSString *)label {
    return _label ?: CamelCaseToSpaces([self key]);
}

- (UIView *)tuningView {
    NSAssert(0, @"%@ must implement %@ and not call super", [self class], NSStringFromSelector(_cmd));
    return nil;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"%@:%@", [self key], [self objectValue]];
}

- (NSDictionary *)jsonRepresentation {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    for (NSString *prop in [[self class] propertiesForJSONRepresentation]) {
        [dict setObject:[self valueForKey:prop] forKey:prop];
    }
    
    return dict;
}

@end

@interface _KFCalloutView : UIView
@property (readonly) UILabel *label;
@end

@implementation _KFCalloutView
- (id)init {
    self = [super init];
    if (self) {
        UIImageView *bezelView = [[UIImageView alloc] init];
        UIImageView *arrowView = [[UIImageView alloc] init];
        UILabel *label = [[UILabel alloc] init];
        [label setTextColor:[UIColor whiteColor]];
        [label setTextAlignment:NSTextAlignmentCenter];
        NSDictionary *views = NSDictionaryOfVariableBindings(bezelView, arrowView, label);
        [views enumerateKeysAndObjectsUsingBlock:^(id key, UIView *view, BOOL *stop) {
            [view setTranslatesAutoresizingMaskIntoConstraints:NO];
        }];
        
        [bezelView addSubview:label];
        [bezelView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-16-[label]-16-|" options:0 metrics:nil views:views]];
        [bezelView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-7-[label]-7-|" options:0 metrics:nil views:views]];

        [self addSubview:bezelView];
        [self addSubview:arrowView];
        [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[bezelView]|" options:0 metrics:nil views:views]];
        [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-(>=5)-[arrowView]-(>=5)-|" options:0 metrics:nil views:views]];
        [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[bezelView]-(-1)-[arrowView]|" options:NSLayoutFormatAlignAllCenterX metrics:nil views:views]];
        
        [bezelView setImage:CalloutBezelImage()];
        [arrowView setImage:CalloutArrowImage()];
        _label = label;
    }
    return self;
}
@end

@interface _KFSilderSpecItem : _KFSpecItem
@property (nonatomic) NSNumber *sliderMinValue;
@property (nonatomic) NSNumber *sliderMaxValue;
@property UIView *container;
@property UISlider *slider;
@property _KFCalloutView *calloutView;
@property NSLayoutConstraint *calloutXCenter;
@end

@implementation _KFSilderSpecItem

+ (NSArray *)propertiesForJSONRepresentation {
    static NSArray *sProps;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sProps = [[super propertiesForJSONRepresentation] arrayByAddingObjectsFromArray:@[@"sliderValue", @"sliderMinValue", @"sliderMaxValue"]];
    });
    return sProps;
}

- (id)initWithJSONRepresentation:(NSDictionary *)json {
    if (json[@"sliderValue"] == nil) {
        return nil;
    } else {
        return [super initWithJSONRepresentation:json];
    }
}

- (UIView *)tuningView {
    if (![self container]) {
        UIView *container = [[UIView alloc] init];
        UISlider *slider = [[UISlider alloc] init];
        _KFCalloutView *callout = [[_KFCalloutView alloc] init];
        NSDictionary *views = NSDictionaryOfVariableBindings(slider, callout);

        [self setSlider:slider];
        [slider setTranslatesAutoresizingMaskIntoConstraints:NO];
        [container addSubview:slider];
        [container addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-0-[slider]-0-|" options:0 metrics:nil views:views]];
        [container addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-0-[slider]-0-|" options:0 metrics:nil views:views]];
        [slider addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"[slider(>=300@720)]" options:0 metrics:nil views:views]];
        [slider addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:[slider(>=25@750)]" options:0 metrics:nil views:views]];

        [slider setMinimumValue:[[self sliderMinValue] doubleValue]];
        [slider setMaximumValue:[[self sliderMaxValue] doubleValue]];
        [self withOwner:self maintain:^(id owner, id objValue) { [slider setValue:[objValue doubleValue]]; }];
        [slider addTarget:self action:@selector(takeSliderValue:) forControlEvents:UIControlEventValueChanged];

        [callout setTranslatesAutoresizingMaskIntoConstraints:NO];
        [container addSubview:callout];
        [container addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:[callout]-3-[slider]" options:0 metrics:nil views:views]];
        [self setCalloutXCenter:[NSLayoutConstraint constraintWithItem:callout attribute:NSLayoutAttributeCenterX relatedBy:NSLayoutRelationEqual toItem:container attribute:NSLayoutAttributeLeft multiplier:1 constant:0]];
        [container addConstraint:[self calloutXCenter]];
        [callout setAlpha:0];

        [self withOwner:self maintain:^(id owner, id objValue) { [[callout label] setText:[NSString stringWithFormat:@"%.2f", [objValue doubleValue]]]; }];
        [slider addTarget:self action:@selector(showCallout:) forControlEvents:UIControlEventTouchDown];
        [slider addTarget:self action:@selector(updateCalloutXCenter:) forControlEvents:UIControlEventValueChanged];
        [slider addTarget:self action:@selector(hideCallout:) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchCancel];
        
        [self setCalloutView:callout];
        [self setContainer:container];
    }
    return [self container];
}

- (void)takeSliderValue:(UISlider *)slider {

    [self setSliderValue:@([slider value])];
}

- (id)sliderValue {
    return [self objectValue];
}

- (void)setSliderValue:(id)sliderValue {

    [self setObjectValue:sliderValue];
}

- (NSNumber *)sliderMinValue {
    return _sliderMinValue ?: @0;
}

- (NSNumber *)sliderMaxValue {
    return _sliderMaxValue ?: @([[self defaultValue] doubleValue]*2);
}

- (void)showCallout:(id)sender {

    [UIView animateWithDuration:0.15 animations:^{
        [[self calloutView] setAlpha:1.0];
    }];
}

- (void)hideCallout:(id)sender {

    [UIView animateWithDuration:0.15 animations:^{
        [[self calloutView] setAlpha:0.0];
    }];
}

- (void)updateCalloutXCenter:(id)sender {
    UISlider *slider = sender;
    CGRect bounds = [slider bounds];
    CGRect thumbRectSliderSpace = [slider thumbRectForBounds:bounds trackRect:[slider trackRectForBounds:bounds] value:[slider value]];
    CGRect thumbRect = [[self container] convertRect:thumbRectSliderSpace fromView:slider];
    [[self calloutXCenter] setConstant:thumbRect.origin.x + thumbRect.size.width/2];
}

@end

typedef NS_ENUM(NSUInteger, KFSliderColorComponent) {
    KFRed,
    KFGreen,
    KFBlue,
    KFAlpha
};
@protocol _KFColorSilderSpecItemDelegate;


@interface _KFColorSilderSpecItem : _KFSpecItem <UIGestureRecognizerDelegate>
@property (nonatomic) NSNumber *sliderMinValue;
@property (nonatomic) NSNumber *sliderMaxValue;
@property UIView *container;
@property NSArray *sliders;
@property _KFCalloutView *calloutView;
@property NSLayoutConstraint *calloutXCenter;
@property NSLayoutConstraint *calloutVConstraint;
@property (nonatomic) NSArray *colorStrings;
@property (nonatomic) KFSliderColorComponent colorComponent;
@property (nonatomic) NSInteger indexOfCurrentSlider; //I don't love that I'm using this. but currently need it for callout label maintin block
@property (nonatomic) NSLayoutConstraint *bottomVerticalConstraint;
@property (nonatomic, weak) id <_KFColorSilderSpecItemDelegate> delegate;
@end
@protocol _KFColorSilderSpecItemDelegate <NSObject>

- (void)updateColorSpecConstraint:(NSLayoutConstraint *)constraint;

@end


@implementation _KFColorSilderSpecItem

+ (NSArray *)propertiesForJSONRepresentation {

    /*only accepts colorValue as an input. rgb values are fixed between 0-255*/
    static NSArray *sProps;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sProps = [[super propertiesForJSONRepresentation] arrayByAddingObjectsFromArray:@[@"colorValue"]];
    });

    return sProps;
}

- (id)initWithJSONRepresentation:(NSDictionary *)json {

    if (json[@"colorValue"] == nil) {
        return nil;
    } else {

        self = [super initWithJSONRepresentation:json];

        return self;
    }
}

- (UIView *)tuningView {
    if (![self container]) {

        self.colorStrings = @[@"Hue", @"Sat.", @"Bright.", @"Alpha"];
        
        UIView *container = [[UIView alloc] init];
        [container setBackgroundColor:[[UIColor whiteColor] colorWithAlphaComponent:0.2]];
        [[container layer] setCornerRadius:5];
        [container setClipsToBounds:YES];

        _KFCalloutView *callout = [[_KFCalloutView alloc] init];
        
        NSMutableArray *temp = [NSMutableArray new];
        for (int i = 0; i < 4; i++) {
            temp[i] = [[UISlider alloc] init];
        }

        [self setSliders:[NSArray arrayWithArray:temp]];
        
        UISlider *lastSlider = nil;
        for (NSInteger i = 0; i < self.sliders.count; i++) { //used for i instead of forin, to ensure correct order
            
            UISlider *currentSlider = self.sliders[i];
            
            [currentSlider setMinimumValue:[[self sliderMinValue] doubleValue]];
            [currentSlider setMaximumValue:[[self sliderMaxValue] doubleValue]];
            
            [currentSlider addTarget:self action:@selector(takeColorSliderValue:) forControlEvents:UIControlEventValueChanged];

            [currentSlider setTranslatesAutoresizingMaskIntoConstraints:NO];
            [container addSubview:currentSlider];

            id sliders = lastSlider ? NSDictionaryOfVariableBindings(currentSlider, lastSlider) : NSDictionaryOfVariableBindings(currentSlider);
            
            [container addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:(lastSlider) ? @"V:[lastSlider]-[currentSlider]" : @"V:|-2-[currentSlider]" options:0 metrics:nil views:sliders]];
            [container addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-5-[currentSlider]-5-|" options:0 metrics:nil views:sliders]];
            [currentSlider addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"[currentSlider(>=300@720)]" options:0 metrics:nil views:sliders]];
            [currentSlider addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:[currentSlider(>=25@750)]" options:0 metrics:nil views:sliders]];
            
            lastSlider = currentSlider;
            [self withOwner:self maintain:^(id owner, id objValue) { [currentSlider setValue:[self valueForSliderAtIndex:i]]; }];

        }
        self.bottomVerticalConstraint = [NSLayoutConstraint constraintsWithVisualFormat:@"V:[lastSlider]-(-110)-|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(lastSlider)].firstObject;
        [container addConstraint:self.bottomVerticalConstraint];

        [callout setTranslatesAutoresizingMaskIntoConstraints:NO];
        [container addSubview:callout];

        UITapGestureRecognizer *dTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)];
        dTap.numberOfTapsRequired = 2;
        dTap.numberOfTouchesRequired = 1;
        
        [container addGestureRecognizer:dTap];
        
        self.calloutVConstraint = [[NSLayoutConstraint constraintsWithVisualFormat:@"V:[callout]-3-[lastSlider]" options:0 metrics:nil views:NSDictionaryOfVariableBindings(lastSlider, callout)] firstObject];
        [container addConstraints:@[self.calloutVConstraint]];
        
        [self setCalloutXCenter:[NSLayoutConstraint constraintWithItem:callout attribute:NSLayoutAttributeCenterX relatedBy:NSLayoutRelationEqual toItem:container attribute:NSLayoutAttributeLeft multiplier:1 constant:0]];
        [container addConstraint:[self calloutXCenter]];
        [callout setAlpha:0];

        [self withOwner:self maintain:^(id owner, id objValue) { [[callout label] setText:[self stringForCalloutView]];
        }];
        for (UISlider *sliderX in self.sliders) {

            [sliderX addTarget:self action:@selector(showCallout:) forControlEvents:UIControlEventTouchDown];
            [sliderX addTarget:self action:@selector(updateCalloutXCenter:) forControlEvents:UIControlEventValueChanged];
            [sliderX addTarget:self action:@selector(hideCallout:) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchCancel];
        }

        [self setCalloutView:callout];
        [self setContainer:container];
    }
    return [self container];
}

-(void)tapped:(UITapGestureRecognizer *)gr {

    [self.delegate updateColorSpecConstraint:self.bottomVerticalConstraint];

}

- (void)takeColorSliderValue:(UISlider *)slider {
    
    //I don't like that I am using a property to track the index of which slider is being used.

    CGFloat sliderIndex = (CGFloat)[self.sliders indexOfObject:slider];
    self.indexOfCurrentSlider = sliderIndex;
    self.calloutVConstraint.constant = 3 + (3 - sliderIndex)*39; //empirically derived number. seems to be the 25 + 7-[label]-7

    CGFloat *components = malloc(4*sizeof(CGFloat));
    
    [self.sliders enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        components[idx] = [(UISlider *)obj value]/[slider maximumValue];
    }];

    [self setColorValue:[self rgbaStringForColor:[UIColor colorWithHue:components[0] saturation:components[1] brightness:components[2] alpha:components[3]]]];

}

- (id)colorValue {
    //this needs to return, just the object value
    return [self objectValue];
}

- (void)setColorValue:(NSString *)color {
    //this needs to take a string
    [self setObjectValue:color];
    
}

- (CGFloat)valueForSliderAtIndex:(NSInteger)index {

    //updated for hue
    CGFloat *components = malloc(4*sizeof(CGFloat));
    if ([colorWithRGBAString([self colorValue]) getHue:&components[0] saturation:&components[1] brightness:&components[2] alpha:&components[3]]) {
        
        return components[index];
        
    }
    

    return 0;
}

- (void)updateSlidersWithValues:(NSArray *)values {

    for (int i = 0; i < 4; i++) {
        UISlider *slider = self.sliders[i];
        [slider setValue:[values[i] floatValue]];
    }
}
- (NSNumber *)sliderMinValue {
    return _sliderMinValue ?: @0;
}

- (NSNumber *)sliderMaxValue {
    return _sliderMaxValue ?: @(1);
}

- (void)showCallout:(id)sender {
    UISlider *slider = sender;
    self.indexOfCurrentSlider = [self.sliders indexOfObject:slider];
    [UIView animateWithDuration:0.15 animations:^{
        [[self calloutView] setAlpha:1.0];
    }];
}

- (void)hideCallout:(id)sender {
    [UIView animateWithDuration:0.15 animations:^{
        [[self calloutView] setAlpha:0.0];

    }];
    
}

- (void)updateCalloutXCenter:(id)sender {

    UISlider *slider = sender;
    CGRect bounds = [slider bounds];
    CGRect thumbRectSliderSpace = [slider thumbRectForBounds:bounds trackRect:[slider trackRectForBounds:bounds] value:[slider value]];
    CGRect thumbRect = [[self container] convertRect:thumbRectSliderSpace fromView:slider];

    [[self calloutXCenter] setConstant:thumbRect.origin.x + thumbRect.size.width/2];
    
}

- (NSString *)stringForCalloutView {
    
    UISlider *s = self.sliders[self.indexOfCurrentSlider];
    return [NSString stringWithFormat:@"%@: %.0f", self.colorStrings[self.indexOfCurrentSlider], 100*[s value]/s.maximumValue];
}

#pragma mark color <--> string methods

- (NSString *)rgbaStringForColor:(UIColor *)color {

    CGFloat *c = malloc(4*sizeof(CGFloat));
    
    if ([color getRed:&c[0] green:&c[1] blue:&c[2] alpha:&c[3]]) {
        return [NSString stringWithFormat:@"rgba(%.0f,%.0f,%.0f,%.3f)", 255*c[0], 255*c[1], 255*c[2], c[3]];

    }

    return @"rgba(0, 0, 0, 1)";
    
}

static BOOL stringIsEmpty(NSString *s) {
	return s == nil || [s length] == 0;
}

static UIColor *colorWithRGBAString(NSString *rgbString) {

    
    if (stringIsEmpty(rgbString)) {
		return [UIColor blackColor];
    }
    
    NSScanner *scanner = [NSScanner scannerWithString:rgbString];
    [scanner setCharactersToBeSkipped:[NSCharacterSet characterSetWithCharactersInString:@"rgba(, "] ];
    float r, g, b, a;
    BOOL scanned;
    
    scanned = [scanner scanFloat:&r];
    scanned = [scanner scanFloat:&g];
    scanned = [scanner scanFloat:&b];
    if (![scanner scanFloat:&a]) { //if only three values entered, assume alpha = 1
        a = 1;
    }
    
    return [UIColor colorWithRed:r/255.0  green:g/255.0  blue:b/255.0 alpha:a];
    
}

@end

@interface _KFSwitchSpecItem : _KFSpecItem
@property UISwitch *uiSwitch;
@end

@implementation _KFSwitchSpecItem

+ (NSArray *)propertiesForJSONRepresentation {
    static NSArray *sProps;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sProps = [[super propertiesForJSONRepresentation] arrayByAddingObjectsFromArray:@[@"switchValue"]];
    });
    return sProps;
}

- (id)initWithJSONRepresentation:(NSDictionary *)json {
    if (json[@"switchValue"] == nil) {
        return nil;
    } else {
        return [super initWithJSONRepresentation:json];
    }
}

- (UIView *)tuningView {
    if (![self uiSwitch]) {
        UISwitch *uiSwitch = [[UISwitch alloc] init];
        [uiSwitch addTarget:self action:@selector(takeSwitchValue:) forControlEvents:UIControlEventValueChanged];
        [self withOwner:self maintain:^(id owner, id objValue) { [uiSwitch setOn:[objValue boolValue]]; }];
        [self setUiSwitch:uiSwitch];
    }
    return [self uiSwitch];
}

- (void)takeSwitchValue:(UISwitch *)uiSwitch {
    [self setSwitchValue:@([uiSwitch isOn])];
}

- (id)switchValue {
    return [self objectValue];
}

- (void)setSwitchValue:(id)switchValue {
    [self setObjectValue:switchValue];
}

@end

@interface HitTransparentWindow : UIWindow
@end
@implementation HitTransparentWindow
-(UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *result = [super hitTest:point withEvent:event];
    if (result == self) {
        result = nil;
    }
    return result;
}
@end


@interface KFTunableSpec () <UIDocumentInteractionControllerDelegate, UIGestureRecognizerDelegate, _KFColorSilderSpecItemDelegate> {
    NSMutableArray *_KFSpecItems;
    NSMutableArray *_savedDictionaryRepresentations;
    NSUInteger _currentSaveIndex;
}
@property UIWindow *window;
@property NSString *name;
@property UIButton *previousButton;
@property UIButton *saveButton;
@property UIButton *defaultsButton;
@property UIButton *revertButton;
@property UIButton *shareButton;
@property UIButton *closeButton;
@property NSLayoutConstraint *controlsXConstraint;
@property NSLayoutConstraint *controlsYConstraint;
@property UIDocumentInteractionController *interactionController; // interaction controller doesn't keep itself alive during presentation. lame.

@end

@implementation KFTunableSpec

static NSMutableDictionary *sSpecsByName;
+(void)initialize {
    if (!sSpecsByName) sSpecsByName = [NSMutableDictionary dictionary];
}

+ (id)specNamed:(NSString *)name {
    KFTunableSpec *spec = sSpecsByName[name];
    if (!spec) {
        spec = [[self alloc] initWithName:name];
        sSpecsByName[name] = spec;
    }
    return spec;
}

- (id)initWithName:(NSString *)name {
    self = [super init];
    if (self) {
        [self setName:name];
        _KFSpecItems = [[NSMutableArray alloc] init];
        _savedDictionaryRepresentations = [NSMutableArray array];
        
        NSParameterAssert(name != nil);
        NSURL *jsonURL = [[NSBundle mainBundle] URLForResource:name withExtension:@"json"];
        NSAssert(jsonURL != nil, @"Missing %@.json in resources directory.", name);
        
        NSData *jsonData = [NSData dataWithContentsOfURL:jsonURL];
        NSError *error = nil;
        
        NSArray *specItemReps = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
        NSAssert(specItemReps != nil, @"error decoding %@.json: %@", name, error);

        for (NSDictionary *rep in specItemReps) {
            _KFSpecItem *specItem = nil;
            specItem = specItem ?: [[_KFColorSilderSpecItem alloc] initWithJSONRepresentation:rep];
            specItem = specItem ?: [[_KFSilderSpecItem alloc] initWithJSONRepresentation:rep];
            specItem = specItem ?: [[_KFSwitchSpecItem alloc] initWithJSONRepresentation:rep];
            if (specItem) {
                [_KFSpecItems addObject:specItem];
            } else {
                NSLog(@"%s: Couldn't read entry %@ in %@. Probably you're missing a key? Check KFTunableSpec.h.", __func__, rep, name);
            }
            
            if ([specItem isKindOfClass:[_KFColorSilderSpecItem class]]) {
                _KFColorSilderSpecItem *temp = (_KFColorSilderSpecItem *)specItem;
                temp.delegate = self;
            }
        }
    }
    return self;
}



- (id)init
{
    return [self initWithName:nil];
}

- (_KFSpecItem *)_KFSpecItemForKey:(NSString *)key {
    for (_KFSpecItem *specItem in _KFSpecItems) {
        if ([[specItem key] isEqual:key]) {
            return specItem;
        }
    
    }

    NSLog(@"%@:Warning – you're trying to use key \"%@\" that doesn't have a valid entry in %@.json. That's unsupported.", [self class], key, [self name]);
    return nil;
}

- (void)addDoubleWithLabel:(NSString *)label forValue:(double)value andMinMaxValues:(NSArray *)minMax {
    //could wrap this into a lazily initiated method from the ***forKey
    NSAssert([minMax count] <= 2, @"this spec requires a min and max value and no other", label);
    //put in the following intake logic
    NSNumber *min = @(0);
    NSNumber *max = @(value*2);
    
    if ([minMax count] == 2) {
        min = minMax[0];
        max = minMax[1];
    } else if ([minMax firstObject] != 0) {
        max = minMax[0];
    }

    NSDictionary *rep = @{@"key" : label, @"label" : label,@"sliderValue" : @(value), @"sliderMinValue" : min, @"sliderMaxValue" : max};

    _KFSpecItem *specItem = [[_KFSilderSpecItem alloc] initWithJSONRepresentation:rep];
    
    if (specItem) {
        [_KFSpecItems addObject:specItem];
    } else {
        NSLog(@"%s: Couldn't read entry %@ in %@. Probably you're missing a key? Check KFTunableSpec.h.", __func__, rep, rep);
    }
}

- (double)doubleForKey:(NSString *)key {
    return [[[self _KFSpecItemForKey:key] objectValue] doubleValue];
}

- (UIColor *)colorForKey:(NSString *)key {
    return colorWithRGBAString([[self _KFSpecItemForKey:key] objectValue]) ;
}


- (void)withDoubleForKey:(NSString *)key owner:(id)weaklyHeldOwner maintain:(void (^)(id owner, double doubleValue))maintenanceBlock {
    [[self _KFSpecItemForKey:key] withOwner:weaklyHeldOwner maintain:^(id owner, id objectValue){
        
        maintenanceBlock(owner, [objectValue doubleValue]);
    }];
}

- (BOOL)boolForKey:(NSString *)key {
    return [[[self _KFSpecItemForKey:key] objectValue] boolValue];
}

- (void)withBoolForKey:(NSString *)key owner:(id)weaklyHeldOwner maintain:(void (^)(id owner, BOOL flag))maintenanceBlock {
    [[self _KFSpecItemForKey:key] withOwner:weaklyHeldOwner maintain:^(id owner, id objectValue){
        maintenanceBlock(owner, [objectValue boolValue]);
    }];
}

- (void)withColorForKey:(NSString *)key owner:(id)weaklyHeldOwner maintain:(void (^)(id owner, UIColor *flag))maintenanceBlock {
    [[self _KFSpecItemForKey:key] withOwner:weaklyHeldOwner maintain:^(id owner, id objectValue) {

        maintenanceBlock(owner, colorWithRGBAString(objectValue));
    }];
}

- (UIViewController *)makeViewController {
    UIView *mainView = [[UIView alloc] init];
    [mainView setBackgroundColor:[[UIColor blackColor] colorWithAlphaComponent:0.6]];
    [[mainView layer] setBorderColor:[[UIColor whiteColor] CGColor]];
    [[mainView layer] setCornerRadius:5];
    //I think that just need to add a scroll view, pin it to mainView, then add views to the scrollview
    UIView *lastControl = nil;
    for (_KFSpecItem *def in _KFSpecItems) {
        UILabel *label = [[UILabel alloc] init];
        [label setTextColor:[UIColor whiteColor]];
        [label setBackgroundColor:[UIColor clearColor]];
        UIView *control = [def tuningView];
        [label setTranslatesAutoresizingMaskIntoConstraints:NO];
        [label setText:[[def label] stringByAppendingString:@":"]];
        [label setTextAlignment:NSTextAlignmentRight];
        id views = lastControl ? NSDictionaryOfVariableBindings(label, control, lastControl) : NSDictionaryOfVariableBindings(label, control);
        [views enumerateKeysAndObjectsUsingBlock:^(NSString *key, id view, BOOL *stop) {
            if (view != lastControl) { // lastControl is already a subview, and adding it again here can change the z-ordering such that it might obstruct a callout.
                [view setTranslatesAutoresizingMaskIntoConstraints:NO];
                [mainView addSubview:view];
            }
        }];
        [mainView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"|-[label]-[control]-(==20@700,>=20)-|" options:NSLayoutFormatAlignAllCenterY metrics:nil views:views]];
        
        if (lastControl) {
            [mainView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:[lastControl]-[control]" options:0 metrics:nil views:views]];
            [mainView addConstraint:[NSLayoutConstraint constraintWithItem:lastControl attribute:NSLayoutAttributeLeading relatedBy:NSLayoutRelationEqual toItem:control attribute:NSLayoutAttributeLeading multiplier:1 constant:0]];
        } else {
            [mainView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-[control]" options:0 metrics:nil views:views]];
        }
        lastControl = control;
    }
    
    NSMutableDictionary *views = [NSMutableDictionary dictionary];
    for (NSString *op in @[@"revert", @"share"]) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeRoundedRect];
        [button setTintColor:[UIColor whiteColor]];
        [button setTitle:[op capitalizedString] forState:UIControlStateNormal];
        [button addTarget:self action:NSSelectorFromString(op) forControlEvents:UIControlEventTouchUpInside];
        [button setTranslatesAutoresizingMaskIntoConstraints:NO];
        [views setObject:button forKey:op];
        [self setValue:button forKey:[op stringByAppendingString:@"Button"]];
        [mainView addSubview:button];
    }
    
    [mainView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-(>=20)-[revert(==share)]-[share]-(>=20)-|" options:NSLayoutFormatAlignAllTop metrics:nil views:views]];
    [mainView addConstraint:[NSLayoutConstraint constraintWithItem:views[@"revert"] attribute:NSLayoutAttributeTrailing relatedBy:NSLayoutRelationEqual toItem:mainView attribute:NSLayoutAttributeCenterX multiplier:1 constant:-10]];
    
    if (lastControl) {
        [views setObject:lastControl forKey:@"lastControl"];
        [mainView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:[lastControl]-[share]-|" options:0 metrics:nil views:views]];
    } else {
        [mainView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-[share]-|" options:0 metrics:nil views:views]];
    }
    
    // We would like to add a close button on the top left corner of the mainView
    // It sticks out a bit from the mainView. In order to have the part that sticks out stay tappable, we make a contentView that completely contains the closeButton and the mainView.

    UIButton *closeButton = [[UIButton alloc] init];
    [closeButton addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    [closeButton setImage:CloseImage() forState:UIControlStateNormal];
    [closeButton setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [closeButton setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    
    UIView *contentView = [[UIView alloc] init];
    [mainView setTranslatesAutoresizingMaskIntoConstraints:NO];
    [closeButton setTranslatesAutoresizingMaskIntoConstraints:NO];
    [contentView addSubview:mainView];
    [contentView addSubview:closeButton];
    
    // perch close button center on contentView corner, slightly inset
    [contentView addConstraint:[NSLayoutConstraint constraintWithItem:closeButton attribute:NSLayoutAttributeCenterX relatedBy:NSLayoutRelationEqual toItem:mainView attribute:NSLayoutAttributeLeading multiplier:1 constant:5]];
    [contentView addConstraint:[NSLayoutConstraint constraintWithItem:closeButton attribute:NSLayoutAttributeCenterY relatedBy:NSLayoutRelationEqual toItem:mainView attribute:NSLayoutAttributeTop multiplier:1 constant:5]];
    
    // center mainView in contentView
    [contentView addConstraint:[NSLayoutConstraint constraintWithItem:mainView attribute:NSLayoutAttributeCenterX relatedBy:NSLayoutRelationEqual toItem:contentView attribute:NSLayoutAttributeCenterX multiplier:1 constant:0]];
    [contentView addConstraint:[NSLayoutConstraint constraintWithItem:mainView attribute:NSLayoutAttributeCenterY relatedBy:NSLayoutRelationEqual toItem:contentView attribute:NSLayoutAttributeCenterY multiplier:1 constant:0]];

    // align edge of close button with contentView
    [contentView addConstraint:[NSLayoutConstraint constraintWithItem:closeButton attribute:NSLayoutAttributeLeading relatedBy:NSLayoutRelationEqual toItem:contentView attribute:NSLayoutAttributeLeading multiplier:1 constant:0]];
    [contentView addConstraint:[NSLayoutConstraint constraintWithItem:closeButton attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:contentView attribute:NSLayoutAttributeTop multiplier:1 constant:0]];

    UIViewController *viewController = [[UIViewController alloc] init];
    [viewController setView:contentView];
//    self.tempView = contentView;
    return viewController;
}

- (void)updateColorSpecConstraint:(NSLayoutConstraint *)constraint {

    [constraint setConstant:(constraint.constant == 2) ? -110 : 2];

    [[self window] setNeedsUpdateConstraints];
    [UIView animateWithDuration:.5 animations:^{
        [[self window] layoutIfNeeded];
    } completion:nil];
    
}


- (BOOL)controlsAreVisible {
    return [self window] != nil;
}

- (void)setControlsAreVisible:(BOOL)flag {
    NSLog(@"%s", __PRETTY_FUNCTION__);

    if (flag && ![self window]) {
        UIViewController *viewController = [self makeViewController];
        UIView *contentView = [viewController view];
        if ([self name]) {
            _savedDictionaryRepresentations = [[[NSUserDefaults standardUserDefaults] objectForKey:[self name]] mutableCopy];
        }
        _savedDictionaryRepresentations = _savedDictionaryRepresentations ?: [[NSMutableArray alloc] init];
        _currentSaveIndex = [_savedDictionaryRepresentations count];
        [self validateButtons];
        
        UIWindow *window = [[HitTransparentWindow alloc] init];
        [window setFrame:[[UIScreen mainScreen] applicationFrame]];
        [window setRootViewController:viewController];
        
        [contentView setTranslatesAutoresizingMaskIntoConstraints:NO];
        [window addSubview:contentView];
        
        // center contentView
        id views = NSDictionaryOfVariableBindings(contentView);
        CGSize limitSize = [[[UIApplication sharedApplication] keyWindow] frame].size;
        id metrics = @{@"widthLimit" : @(limitSize.width), @"heightLimit" : @(limitSize.height)};
        [contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:[contentView(<=widthLimit)]" options:0 metrics:metrics views:views]];
        [contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:[contentView(<=heightLimit)]" options:0 metrics:metrics views:views]];
    
        UIGestureRecognizer *moveWindowReco = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(moveWindowWithReco:)];
        [contentView addGestureRecognizer:moveWindowReco];
        [moveWindowReco setDelegate:self];
        
        [self setControlsXConstraint:[NSLayoutConstraint constraintWithItem:contentView attribute:NSLayoutAttributeCenterX relatedBy:NSLayoutRelationEqual toItem:window attribute:NSLayoutAttributeCenterX multiplier:1 constant:0]];
        [self setControlsYConstraint:[NSLayoutConstraint constraintWithItem:contentView attribute:NSLayoutAttributeCenterY relatedBy:NSLayoutRelationEqual toItem:window attribute:NSLayoutAttributeCenterY multiplier:1 constant:0]];
        
        [window addConstraint:[self controlsXConstraint]];
        [window addConstraint:[self controlsYConstraint]];
        
        [window makeKeyAndVisible];
        [self setWindow:window];
    }
    if (!flag && [self window]) {
        UIWindow *window = [self window];
        [window setHidden:YES];
        _savedDictionaryRepresentations = nil;
        [self setControlsXConstraint:nil];
        [self setControlsYConstraint:nil];
        [self setWindow:nil];
    }
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    // it's disconcerting when you're going for a slider and move the window instead
    UIView *hitView = [[gestureRecognizer view] hitTest:[gestureRecognizer locationInView:[gestureRecognizer view]] withEvent:nil];
    if ([hitView isKindOfClass:[UIControl class]]) {
        return NO;
    } else {
        return YES;
    }
}

- (void)moveWindowWithReco:(UIPanGestureRecognizer *)reco {
    switch (reco.state) {
        case UIGestureRecognizerStateBegan: {
            [reco setTranslation:CGPointMake([[self controlsXConstraint] constant], [[self controlsYConstraint] constant]) inView:[self window]];
            break;
        }
        case UIGestureRecognizerStateChanged: {
            CGPoint trans = [reco translationInView:[self window]];
            [[self controlsXConstraint] setConstant:trans.x];
            [[self controlsYConstraint] setConstant:trans.y];
        }
        case UIGestureRecognizerStatePossible:
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed:
            break;
    }
}

- (UIGestureRecognizer *)twoFingerTripleTapGestureRecognizer {
    UITapGestureRecognizer *reco = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_toggleVisible:)];
    [reco setNumberOfTapsRequired:3];
    [reco setNumberOfTouchesRequired:2];
    return reco;
}

- (void)_toggleVisible:(id)sender {
    [self setControlsAreVisible:![self controlsAreVisible]];
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    for (_KFSpecItem *def in _KFSpecItems) {
        dict[[def key]] = [def objectValue];
    }
    return dict;
}

- (void)restoreFromDictionaryRepresentation:(NSDictionary *)dictionaryRep {
    for (_KFSpecItem *def in _KFSpecItems) {
        id savedVal = [dictionaryRep objectForKey:[def key]];
        if (savedVal) [def setObjectValue:savedVal];
    }
}

- (id)jsonRepresentation {
    NSMutableArray *json = [NSMutableArray array];
    for (_KFSpecItem *def in _KFSpecItems) {
        [json addObject:[def jsonRepresentation]];
    }
    return json;
}

- (NSString *)description {
    NSMutableString *desc = [NSMutableString stringWithFormat:@"<%@:%p \"%@\"", [self class], self, [self name]];
    for (_KFSpecItem *item in _KFSpecItems) {
        [desc appendFormat:@" %@", [item description]];
    }
    [desc appendString:@">"];
    return desc;
}

- (void)log {
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:[self jsonRepresentation] options:NSJSONWritingPrettyPrinted error:NULL];
    NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    NSLog(@"\n%@", jsonString);
    
}

- (void)save {
    NSDictionary *savedDict = [self dictionaryRepresentation];
    [_savedDictionaryRepresentations addObject:savedDict];
    _currentSaveIndex = [_savedDictionaryRepresentations count];
    [self validateButtons];
    
    if ([self name]) {
        [[NSUserDefaults standardUserDefaults] setObject:_savedDictionaryRepresentations forKey:[self name]];
    }
    
    [self log];
}

- (void)previous {
    if (_currentSaveIndex > 0) {
        _currentSaveIndex--;
        NSDictionary *savedDict = _savedDictionaryRepresentations[_currentSaveIndex];
        [self restoreFromDictionaryRepresentation:savedDict];
    }
    [self validateButtons];
}

- (void)defaults {
    [self log];
    for (_KFSpecItem *item in _KFSpecItems) {
        [item setObjectValue:[item defaultValue]];
    }
    [self validateButtons];
    [self log];
}

- (void)revert {
    [self defaults];
}

- (void)share {
    [self log];
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:[self jsonRepresentation] options:NSJSONWritingPrettyPrinted error:&error];
    NSString *tempFilename = [[self name] ?: @"UnnamedSpec" stringByAppendingPathExtension:@"json"];
    NSURL *tempFileURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:tempFilename] isDirectory:NO];
    [data writeToURL:tempFileURL atomically:YES];
    UIDocumentInteractionController *interactionController = [UIDocumentInteractionController interactionControllerWithURL:tempFileURL];
    [self setInteractionController:interactionController];
    [interactionController setDelegate:self];
    [interactionController presentOptionsMenuFromRect:[[self shareButton] bounds] inView:[self shareButton] animated:YES];
}

- (void)documentInteractionControllerDidDismissOptionsMenu:(UIDocumentInteractionController *)controller {
    [self didFinishShare];
}

- (void)documentInteractionControllerDidDismissOpenInMenu:(UIDocumentInteractionController *)controller {
    [self didFinishShare];
}

- (void)didFinishShare {
    [self setInteractionController:nil];
}

- (void)close {
    [self setControlsAreVisible:NO];
}


- (void)validateButtons {
    [[self previousButton] setEnabled:(_currentSaveIndex > 0)];
}


@end

static UIColor *CalloutColor() {
    return [UIColor colorWithWhite:0.219f alpha:1.0];
}

static UIImage *CalloutBezelImage() {
    static UIImage *bezelImage;
    if (!bezelImage) {
        CGFloat bezelRadius = 5.5;
        CGFloat ceilBezelRadius = ceil(bezelRadius);
        CGRect bounds = CGRectMake(0, 0, ceilBezelRadius*2+1, ceilBezelRadius*2+1);
        UIGraphicsBeginImageContextWithOptions(bounds.size, NO, [[UIScreen mainScreen] scale]);
        [CalloutColor() setFill];
        [[UIBezierPath bezierPathWithRoundedRect:bounds cornerRadius:bezelRadius] fill];
        UIImage *roundRectImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        bezelImage = [roundRectImage resizableImageWithCapInsets:UIEdgeInsetsMake(ceilBezelRadius, ceilBezelRadius, ceilBezelRadius, ceilBezelRadius)];
    }
    return bezelImage;
}

static UIImage *CalloutArrowImage() {
    static UIImage *arrowImage;
    if (!arrowImage) {
        CGFloat arrowHeight = 10;
        CGRect bounds = CGRectMake(0, 0, (arrowHeight+1)*2, arrowHeight+1);
        UIGraphicsBeginImageContextWithOptions(bounds.size, NO, [[UIScreen mainScreen] scale]);
        [CalloutColor() setFill];
        UIBezierPath *bezierPath = [[UIBezierPath alloc] init];
        [bezierPath moveToPoint:CGPointMake(0,0)];
        [bezierPath addLineToPoint:CGPointMake(bounds.size.width/2, bounds.size.height)];
        [bezierPath addLineToPoint:CGPointMake(bounds.size.width, 0)];
        [bezierPath setLineJoinStyle:kCGLineJoinRound];
        [bezierPath fill];
        arrowImage = UIGraphicsGetImageFromCurrentImageContext();
    }
    return arrowImage;
}


// drawing code generated by http://likethought.com/opacity/
// (I just didn't want to require including image files)

const CGFloat kDrawCloseArtworkWidth = 30.0f;
const CGFloat kDrawCloseArtworkHeight = 30.0f;

static void DrawCloseArtwork(CGContextRef context, CGRect bounds)
{
    CGRect imageBounds = CGRectMake(0.0f, 0.0f, kDrawCloseArtworkWidth, kDrawCloseArtworkHeight);
    CGFloat alignStroke;
    CGFloat resolution;
    CGMutablePathRef path;
    CGRect drawRect;
    CGColorRef color;
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGFloat stroke;
    CGPoint point;
    CGAffineTransform transform;
    CGFloat components[4];
    
    transform = CGContextGetUserSpaceToDeviceSpaceTransform(context);
    resolution = sqrtf(fabsf(transform.a * transform.d - transform.b * transform.c)) * 0.5f * (bounds.size.width / imageBounds.size.width + bounds.size.height / imageBounds.size.height);
    
    CGContextSaveGState(context);
    CGContextClipToRect(context, bounds);
    CGContextTranslateCTM(context, bounds.origin.x, bounds.origin.y);
    CGContextScaleCTM(context, (bounds.size.width / imageBounds.size.width), (bounds.size.height / imageBounds.size.height));
    
    // Layer 1
    
    alignStroke = 0.0f;
    path = CGPathCreateMutable();
    drawRect = CGRectMake(0.0f, 0.0f, 30.0f, 30.0f);
    drawRect.origin.x = (roundf(resolution * drawRect.origin.x + alignStroke) - alignStroke) / resolution;
    drawRect.origin.y = (roundf(resolution * drawRect.origin.y + alignStroke) - alignStroke) / resolution;
    drawRect.size.width = roundf(resolution * drawRect.size.width) / resolution;
    drawRect.size.height = roundf(resolution * drawRect.size.height) / resolution;
    CGPathAddEllipseInRect(path, NULL, drawRect);
    components[0] = 0.219f;
    components[1] = 0.219f;
    components[2] = 0.219f;
    components[3] = 1.0f;
    color = CGColorCreate(space, components);
    CGContextSetFillColorWithColor(context, color);
    CGColorRelease(color);
    CGContextAddPath(context, path);
    CGContextFillPath(context);
    components[0] = 1.0f;
    components[1] = 1.0f;
    components[2] = 1.0f;
    components[3] = 1.0f;
    color = CGColorCreate(space, components);
    CGContextSetStrokeColorWithColor(context, color);
    CGColorRelease(color);
    stroke = 2.0f;
    stroke *= resolution;
    if (stroke < 1.0f) {
        stroke = ceilf(stroke);
    } else {
        stroke = roundf(stroke);
    }
    stroke /= resolution;
    stroke *= 2.0f;
    CGContextSetLineWidth(context, stroke);
    CGContextSetLineCap(context, kCGLineCapSquare);
    CGContextSaveGState(context);
    CGContextAddPath(context, path);
    CGContextEOClip(context);
    CGContextAddPath(context, path);
    CGContextStrokePath(context);
    CGContextRestoreGState(context);
    CGPathRelease(path);
    
    stroke = 2.5f;
    stroke *= resolution;
    if (stroke < 1.0f) {
        stroke = ceilf(stroke);
    } else {
        stroke = roundf(stroke);
    }
    stroke /= resolution;
    alignStroke = fmodf(0.5f * stroke * resolution, 1.0f);
    path = CGPathCreateMutable();
    point = CGPointMake(10.0f, 20.0f);
    point.x = (roundf(resolution * point.x + alignStroke) - alignStroke) / resolution;
    point.y = (roundf(resolution * point.y + alignStroke) - alignStroke) / resolution;
    CGPathMoveToPoint(path, NULL, point.x, point.y);
    point = CGPointMake(20.0f, 10.0f);
    point.x = (roundf(resolution * point.x + alignStroke) - alignStroke) / resolution;
    point.y = (roundf(resolution * point.y + alignStroke) - alignStroke) / resolution;
    CGPathAddLineToPoint(path, NULL, point.x, point.y);
    components[0] = 1.0f;
    components[1] = 1.0f;
    components[2] = 1.0f;
    components[3] = 1.0f;
    color = CGColorCreate(space, components);
    CGContextSetStrokeColorWithColor(context, color);
    CGColorRelease(color);
    CGContextSetLineWidth(context, stroke);
    CGContextSetLineCap(context, kCGLineCapRound);
    CGContextSetLineJoin(context, kCGLineJoinRound);
    CGContextAddPath(context, path);
    CGContextStrokePath(context);
    CGPathRelease(path);
    
    stroke = 2.5f;
    stroke *= resolution;
    if (stroke < 1.0f) {
        stroke = ceilf(stroke);
    } else {
        stroke = roundf(stroke);
    }
    stroke /= resolution;
    alignStroke = fmodf(0.5f * stroke * resolution, 1.0f);
    path = CGPathCreateMutable();
    point = CGPointMake(10.0f, 10.0f);
    point.x = (roundf(resolution * point.x + alignStroke) - alignStroke) / resolution;
    point.y = (roundf(resolution * point.y + alignStroke) - alignStroke) / resolution;
    CGPathMoveToPoint(path, NULL, point.x, point.y);
    point = CGPointMake(20.0f, 20.0f);
    point.x = (roundf(resolution * point.x + alignStroke) - alignStroke) / resolution;
    point.y = (roundf(resolution * point.y + alignStroke) - alignStroke) / resolution;
    CGPathAddLineToPoint(path, NULL, point.x, point.y);
    components[0] = 1.0f;
    components[1] = 1.0f;
    components[2] = 1.0f;
    components[3] = 1.0f;
    color = CGColorCreate(space, components);
    CGContextSetStrokeColorWithColor(context, color);
    CGColorRelease(color);
    CGContextAddPath(context, path);
    CGContextStrokePath(context);
    CGPathRelease(path);
    
    CGContextRestoreGState(context);
    CGColorSpaceRelease(space);
}

static UIImage *CloseImage() {
    CGRect bounds = CGRectMake(0, 0, kDrawCloseArtworkWidth, kDrawCloseArtworkHeight);
    UIGraphicsBeginImageContextWithOptions(bounds.size, NO, [[UIScreen mainScreen] scale]);
    DrawCloseArtwork(UIGraphicsGetCurrentContext(), bounds);
    UIImage *closeImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return closeImage;
}

