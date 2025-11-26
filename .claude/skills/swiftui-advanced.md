---
name: swiftui-advanced
description: Deep expertise for advanced SwiftUI patterns including custom view modifiers, GeometryReader, animations, custom layouts, PreferenceKey/EnvironmentKey, and performance optimization. Use when building complex UI, custom layouts, advanced animations, or optimizing SwiftUI performance.
---

# SwiftUI Advanced Patterns - Deep Dive

Expert guidance for advanced SwiftUI techniques with focus on custom layouts, performance, and sophisticated UI patterns.

## When to Use This Skill

- Building complex custom layouts that go beyond stacks and grids
- Creating reusable view modifiers and result builders
- Implementing sophisticated animations and transitions
- Using GeometryReader for dynamic layouts
- Creating custom environment values or preference keys
- Optimizing SwiftUI performance (view body calculations, update frequency)
- Debugging view update cycles and hitches

## Custom View Modifiers

### Basic Pattern

```swift
struct BorderedCaption: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.caption2)
            .padding(10)
            .overlay(
                RoundedRectangle(cornerRadius: 15)
                    .stroke(lineWidth: 1)
            )
            .foregroundColor(Color.blue)
    }
}

// Idiomatic extension
extension View {
    func borderedCaption() -> some View {
        modifier(BorderedCaption())
    }
}

// Usage
Text("Downtown Bus")
    .borderedCaption()
```

**When to use:**
- Combining multiple modifiers into a reusable unit
- Creating domain-specific view styling (`.cardStyle()`, `.headerStyle()`)
- Reducing code duplication across views

**From Apple Docs:**
- `ViewModifier` protocol requires implementing `body(content: Content) -> some View`
- Use extension on `View` for cleaner call sites
- Types inherit `@MainActor` isolation by default

### Parameterized View Modifiers

```swift
struct ConditionalBorder: ViewModifier {
    let isHighlighted: Bool
    let color: Color

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(color, lineWidth: isHighlighted ? 3 : 1)
            )
    }
}

extension View {
    func conditionalBorder(isHighlighted: Bool, color: Color = .blue) -> some View {
        modifier(ConditionalBorder(isHighlighted: isHighlighted, color: color))
    }
}
```

## GeometryReader - Measured Layouts

### Understanding GeometryReader

**From Apple Docs:**
> A container view that defines its content as a function of its own size and coordinate space. This view returns a flexible preferred size to its parent layout.

**Key insight:** GeometryReader proposes its content the full space available, then reports back a size based on its content.

### Basic Pattern

```swift
GeometryReader { geometry in
    Text("Width: \(geometry.size.width)")
        .frame(width: geometry.size.width * 0.8)
}
```

### Advanced: Adaptive Layout Based on Geometry

**From HealthTrends:** Dynamic spacing based on available height

```swift
// From EnergyTrendView.swift:16-32
GeometryReader { geometry in
    let spacing = geometry.size.height > 300 ? 16.0 : 8.0

    VStack(spacing: spacing) {
        HStack(spacing: 0) {
            HeaderStatistic(label: "Today", statistic: todayTotal, color: activeEnergyColor)
                .frame(maxWidth: .infinity, alignment: .leading)

            HeaderStatistic(label: "Average", statistic: averageAtCurrentHour, color: Color(.systemGray))
                .frame(maxWidth: .infinity, alignment: .center)

            HeaderStatistic(label: "Total", statistic: projectedTotal, color: Color(.systemGray2))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .fixedSize(horizontal: false, vertical: true)

        ContentView(/* ... */)
            .frame(maxHeight: .infinity)
    }
}
```

**Pattern:** Use available size to make layout decisions (spacing, sizing, visibility)

### GeometryReader Performance Considerations

**From Apple Docs - Understanding and Improving SwiftUI Performance:**

> Layout readers, for example, `GeometryReader` and `ScrollViewReader`, observe layout changes in their parent views to recalculate their layouts. Reduce the scope of simultaneous layout and state updates by moving views with state dependencies that don't affect the layout into a separate view hierarchy.

**Practical advice:**
- Don't nest GeometryReader unnecessarily
- Calculate geometry once, not in loops
- Extract geometry-dependent logic to separate views

**Anti-pattern:**
```swift
// ❌ BAD: Recalculates geometry 24 times
AxisMarks(values: .stride(by: .hour, count: 1)) { value in
    GeometryReader { geometry in
        // This runs 24 times!
        let position = calculatePosition(geometry.size.width)
        // ...
    }
}
```

**Better pattern:**
```swift
// ✅ GOOD: Calculate once, use many times
GeometryReader { geometry in
    let width = geometry.size.width
    let itemWidth = width / CGFloat(items.count)

    HStack(spacing: 0) {
        ForEach(items) { item in
            // Uses pre-calculated itemWidth
            ItemView(item, width: itemWidth)
        }
    }
}
```

## Result Builders (@ViewBuilder)

### Understanding @ViewBuilder

**From Apple Docs:**
> A custom parameter attribute that constructs views from closures. You typically use `ViewBuilder` as a parameter attribute for child view-producing closure parameters, allowing those closures to provide multiple child views.

### Using @ViewBuilder for Custom Views

```swift
struct ConditionalContainer<Content: View>: View {
    let showBorder: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        if showBorder {
            content()
                .padding()
                .border(Color.blue, width: 2)
        } else {
            content()
        }
    }
}

// Usage - accepts multiple views thanks to @ViewBuilder
ConditionalContainer(showBorder: true) {
    Text("First line")
    Text("Second line")
    Image(systemName: "star")
}
```

**Pattern:** Use @ViewBuilder to accept multiple child views in custom containers

## Animations & Transitions

### withAnimation - State-Based Animation

**From Apple Docs:**
> Returns the result of recomputing the view's body with the provided animation. This function sets the given `Animation` as the `animation` property of the thread's current `Transaction`.

```swift
withAnimation(.easeInOut(duration: 0.3)) {
    isExpanded.toggle()
}
```

**With completion:**
```swift
withAnimation(.spring, completionCriteria: .logicallyComplete) {
    offset = 100
} completion: {
    print("Animation finished")
}
```

### Implicit vs Explicit Animation

**Implicit (modifier-based):**
```swift
Circle()
    .fill(isActive ? .red : .blue)
    .animation(.easeInOut, value: isActive)  // Animates color change
```

**Explicit (withAnimation):**
```swift
Button("Toggle") {
    withAnimation {
        isActive.toggle()  // Animates all changes in closure
    }
}
```

### Custom Transitions

```swift
extension AnyTransition {
    static var slideAndFade: AnyTransition {
        AnyTransition.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }
}

// Usage
if showDetails {
    DetailView()
        .transition(.slideAndFade)
}
```

### Matched Geometry Effect

```swift
@Namespace private var animation

// Source view
Circle()
    .matchedGeometryEffect(id: "circle", in: animation)
    .frame(width: 50, height: 50)

// Destination view (appears with smooth morphing)
Circle()
    .matchedGeometryEffect(id: "circle", in: animation)
    .frame(width: 200, height: 200)
```

## Custom Environment Values

### Creating Environment Keys

**From Apple Docs - EnvironmentKey:**

```swift
private struct MyEnvironmentKey: EnvironmentKey {
    static let defaultValue: String = "Default value"
}

extension EnvironmentValues {
    var myCustomValue: String {
        get { self[MyEnvironmentKey.self] }
        set { self[MyEnvironmentKey.self] = newValue }
    }
}

// Convenience modifier
extension View {
    func myCustomValue(_ value: String) -> some View {
        environment(\.myCustomValue, value)
    }
}

// Set value
MyView()
    .myCustomValue("Another string")

// Read value
struct MyView: View {
    @Environment(\.myCustomValue) var customValue: String

    var body: some View {
        Text(customValue)  // Displays "Another string"
    }
}
```

**Use cases:**
- Dependency injection (HealthKitService, formatters)
- Theme/styling configuration
- Feature flags
- Accessibility preferences

**Example: Injecting HealthKit service**

```swift
private struct HealthKitServiceKey: EnvironmentKey {
    static let defaultValue: HealthKitQueryService = HealthKitQueryService()
}

extension EnvironmentValues {
    var healthKitService: HealthKitQueryService {
        get { self[HealthKitServiceKey.self] }
        set { self[HealthKitServiceKey.self] = newValue }
    }
}

// Usage in views
struct ContentView: View {
    @Environment(\.healthKitService) var healthKit

    var body: some View {
        Button("Fetch Data") {
            Task {
                let data = try await healthKit.fetchTodayHourlyTotals()
            }
        }
    }
}
```

## PreferenceKey - Child-to-Parent Communication

### Understanding PreferenceKey

**From Apple Docs:**
> A named value produced by a view. A view with multiple children automatically combines its values for a given preference into a single value visible to its ancestors.

**Pattern:** Child views produce values → PreferenceKey aggregates → Parent consumes

### Basic Example: Measuring View Sizes

```swift
struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()  // Last child wins
    }
}

// Helper modifier
extension View {
    func reportSize(_ size: Binding<CGSize>) -> some View {
        background(
            GeometryReader { geometry in
                Color.clear
                    .preference(key: SizePreferenceKey.self, value: geometry.size)
            }
        )
        .onPreferenceChange(SizePreferenceKey.self) { newSize in
            size.wrappedValue = newSize
        }
    }
}

// Usage
struct ParentView: View {
    @State private var childSize: CGSize = .zero

    var body: some View {
        VStack {
            Text("Child size: \(childSize.width) x \(childSize.height)")

            ChildView()
                .reportSize($childSize)
        }
    }
}
```

### Advanced: Aggregating Multiple Values

```swift
struct OffsetPreferenceKey: PreferenceKey {
    static var defaultValue: [CGFloat] = []

    static func reduce(value: inout [CGFloat], nextValue: () -> [CGFloat]) {
        value.append(contentsOf: nextValue())  // Collect all offsets
    }
}

// Track scroll positions of multiple subviews
ScrollView {
    ForEach(items) { item in
        ItemView(item)
            .background(
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: OffsetPreferenceKey.self,
                        value: [geometry.frame(in: .named("scroll")).minY]
                    )
                }
            )
    }
}
.coordinateSpace(name: "scroll")
.onPreferenceChange(OffsetPreferenceKey.self) { offsets in
    // offsets contains Y position of every item
}
```

## SwiftUI Performance Optimization

### Key Principles from Apple Docs

**From "Understanding and Improving SwiftUI Performance":**

1. **Keep view bodies fast**
   - View bodies recalculate frequently
   - Avoid expensive work in `body`, `onAppear`, `onChanged`
   - Move business logic to model types

2. **Avoid storing closures in views**
   - Closures capture state, causing extra updates
   - Store closure results, not closures themselves

3. **Reduce update frequency**
   - Use `@Observable` macro (tracks property access)
   - Scope updates to relevant views only

### Performance Anti-Patterns

**❌ Expensive work in body:**
```swift
struct MyView: View {
    let items: [Item]

    var body: some View {
        let processedItems = items.map { expensiveTransform($0) }  // BAD!

        List(processedItems) { item in
            ItemRow(item)
        }
    }
}
```

**✅ Pre-compute or cache:**
```swift
struct MyView: View {
    let items: [Item]

    // Computed once during init or when items change
    private let processedItems: [ProcessedItem]

    init(items: [Item]) {
        self.items = items
        self.processedItems = items.map { expensiveTransform($0) }
    }

    var body: some View {
        List(processedItems) { item in
            ItemRow(item)
        }
    }
}
```

### Minimizing View Updates

**From HealthTrends:** Timer with minute-boundary detection

```swift
// From ContentView.swift:15, 21-22, 80-101
@State private var lastRefreshMinute: Int = Calendar.current.component(.minute, from: Date())
private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

.onReceive(timer) { _ in
    // Only refresh when we cross a minute boundary
    let currentMinute = Calendar.current.component(.minute, from: Date())
    guard currentMinute != lastRefreshMinute else { return }
    lastRefreshMinute = currentMinute

    // Refresh data at the start of each new minute
    Task {
        guard healthKitManager.isAuthorized else { return }
        try? await healthKitManager.fetchEnergyData()
        // ...
    }
}
```

**Pattern:** Check second-by-second, only update when meaningful change occurs (new minute)

### Using Instruments to Profile SwiftUI

**From Apple Docs:**

1. **SwiftUI Instrument** - Shows view body updates, hitches, update groups
2. **Time Profiler** - Identifies slow code during updates
3. **Hangs Instrument** - Detects blocked main thread

**Workflow:**
1. Record with SwiftUI instrument
2. Identify long-running view body updates in timeline
3. Set inspection range on long update
4. Switch to Time Profiler to see call stack
5. Optimize identified code

**Common issues revealed by Instruments:**
- Expensive calculations in view body
- Too-frequent updates (observing unnecessary properties)
- GeometryReader causing cascading layout updates
- Closures capturing excessive state

## Layout Protocol (iOS 16+)

### Custom Layout Containers

**From Apple Docs - Layout Protocol:**

```swift
struct BasicVStack: Layout {
    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        // Calculate size container needs
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let totalHeight = sizes.reduce(0) { $0 + $1.height }
        let maxWidth = sizes.map(\.width).max() ?? 0
        return CGSize(width: maxWidth, height: totalHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var y = bounds.minY
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            subview.place(
                at: CGPoint(x: bounds.minX, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
            y += size.height
        }
    }
}

// Usage
BasicVStack {
    Text("First")
    Text("Second")
    Text("Third")
}
```

### Layout with Parameters

```swift
struct FlexibleStack: Layout {
    var spacing: CGFloat = 8
    var alignment: HorizontalAlignment = .leading

    func sizeThatFits(/* ... */) -> CGSize {
        // Use self.spacing in calculations
    }

    func placeSubviews(/* ... */) {
        // Use self.alignment when placing
    }
}

// Usage
FlexibleStack(spacing: 16, alignment: .center) {
    Text("Item 1")
    Text("Item 2")
}
```

**When to use Layout protocol:**
- Complex custom layouts (masonry, flow, radial)
- Layouts that don't fit stack/grid paradigm
- Performance-critical layouts (custom measurement logic)

## State Management Patterns

### @StateObject vs @ObservedObject

**@StateObject:** View owns and creates the object
```swift
struct ContentView: View {
    @StateObject private var healthKitManager = HealthKitManager()  // ✅ View creates
}
```

**@ObservedObject:** View receives object from parent
```swift
struct DetailView: View {
    @ObservedObject var healthKitManager: HealthKitManager  // ✅ Parent passes
}
```

**@Observable (iOS 17+):** Automatic fine-grained tracking
```swift
@Observable
final class ViewModel {
    var name: String = ""
    var age: Int = 0
}

struct MyView: View {
    var model: ViewModel

    var body: some View {
        // Only updates when `name` changes (not when `age` changes)
        Text(model.name)
    }
}
```

### Scene Phase Handling

**From HealthTrends:** Refresh on foreground

```swift
// From ContentView.swift:16, 120-137
@Environment(\.scenePhase) private var scenePhase

.onChange(of: scenePhase) { oldPhase, newPhase in
    // Refresh data when app comes to foreground
    if newPhase == .active && healthKitManager.isAuthorized {
        Task {
            try? await healthKitManager.fetchEnergyData()
            try await healthKitManager.fetchMoveGoal()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
```

**Pattern:** Use scene phase to respond to app lifecycle events

## Common Pitfalls & Solutions

### Issue: GeometryReader Takes Full Space

**Problem:** GeometryReader expands to fill available space

```swift
// ❌ Takes entire screen height
VStack {
    Text("Header")
    GeometryReader { geometry in
        Text("Width: \(geometry.size.width)")
    }
    Text("Footer")  // Pushed to bottom!
}
```

**Solution:** Constrain GeometryReader height

```swift
// ✅ Fixed height
GeometryReader { geometry in
    Text("Width: \(geometry.size.width)")
}
.frame(height: 50)

// Or use .fixedSize
GeometryReader { geometry in
    Text("Width: \(geometry.size.width)")
}
.fixedSize(horizontal: false, vertical: true)
```

### Issue: View Updates Too Frequently

**Symptom:** Performance hitches, battery drain, UI lag

**Debug with Instruments:**
1. Open Instruments → SwiftUI instrument
2. Look for frequent updates in Update Groups timeline
3. Use "Show Causes" to see update chain
4. Identify unnecessary observable properties

**Solution:** Narrow observation scope

```swift
// ❌ Updates when ANY property changes
@ObservedObject var manager: DataManager

var body: some View {
    Text(manager.displayName)  // Updates when unrelated properties change!
}

// ✅ Migrate to @Observable (iOS 17+) - tracks property access
@Observable
final class DataManager {
    var displayName: String
    var internalState: Int  // Changes don't trigger update!
}
```

### Issue: Animations Don't Work

**Common causes:**

1. **Missing animation modifier:**
```swift
// ❌ No animation
@State private var scale: CGFloat = 1.0

Circle()
    .scaleEffect(scale)

Button("Grow") { scale = 2.0 }

// ✅ Add animation
Circle()
    .scaleEffect(scale)
    .animation(.spring, value: scale)
```

2. **Wrong animation scope:**
```swift
// ❌ Animating non-animatable type
struct MyShape: Shape {
    var animatableData: AnimatablePair<CGFloat, CGFloat>  // Must implement!
}
```

3. **Identity changes breaking animation:**
```swift
// ❌ SwiftUI sees this as remove + insert (no animation)
if showDetails {
    DetailView()
        .id(UUID())  // New identity every render!
}

// ✅ Stable identity
if showDetails {
    DetailView()
        .transition(.slide)
}
```

## Testing & Debugging

### Preview Providers

```swift
#Preview {
    EnergyTrendView(
        todayTotal: 467,
        averageAtCurrentHour: 389,
        todayHourlyData: generateSampleData(),
        averageHourlyData: generateSampleData(),
        moveGoal: 800,
        projectedTotal: 1034
    )
}

#Preview("Dark Mode") {
    EnergyTrendView(/* ... */)
        .preferredColorScheme(.dark)
}

#Preview("Large Font") {
    EnergyTrendView(/* ... */)
        .environment(\.dynamicTypeSize, .xxxLarge)
}
```

### Debug View Updates

```swift
extension View {
    func debugPrint(_ message: String) -> some View {
        print("🔄 \(message)")
        return self
    }
}

// Usage
var body: some View {
    Text("Hello")
        .debugPrint("Text body evaluated")  // Logs when body runs
}
```

### Debug Performance

```swift
// Measure view rendering time
var body: some View {
    let start = CFAbsoluteTimeGetCurrent()
    defer {
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        print("⏱️ Body took \(elapsed)ms")
    }

    return Text("Hello")
}
```

## Best Practices Summary

1. **Custom View Modifiers:** Use for reusable styling, combine extensions for clean call sites
2. **GeometryReader:** Calculate once, pass to children; avoid nesting; constrain size
3. **Result Builders:** Extract complex view composition into computed properties
4. **Performance:** Keep body fast, avoid closures in views, calculate outside loops
5. **Animations:** Use `.animation(_:value:)` for implicit, `withAnimation` for explicit
6. **Environment:** Use for dependency injection, avoid excessive environment reads
7. **PreferenceKey:** For child→parent communication, aggregate multiple values
8. **State:** @StateObject for ownership, @ObservedObject for passing, @Observable for fine-grained tracking
9. **Layout Protocol:** For complex custom layouts beyond stack/grid
10. **Instruments:** Profile with SwiftUI instrument, optimize based on data

## References

- Apple Docs: [ViewBuilder](https://developer.apple.com/documentation/swiftui/viewbuilder/)
- Apple Docs: [ViewModifier](https://developer.apple.com/documentation/swiftui/viewmodifier/)
- Apple Docs: [GeometryReader](https://developer.apple.com/documentation/swiftui/geometryreader/)
- Apple Docs: [PreferenceKey](https://developer.apple.com/documentation/swiftui/preferencekey/)
- Apple Docs: [EnvironmentKey](https://developer.apple.com/documentation/swiftui/environmentkey/)
- Apple Docs: [Layout Protocol](https://developer.apple.com/documentation/swiftui/layout/)
- Apple Docs: [Understanding and Improving SwiftUI Performance](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance/)
- Apple Docs: [withAnimation](https://developer.apple.com/documentation/swiftui/withanimation(_:_:)/)
- HealthTrends: `EnergyTrendView.swift`, `ContentView.swift`

## See Also

- **swift-charts-advanced skill**: For advanced Swift Charts patterns including @ChartContentBuilder, label collision detection, custom axis marks
- **healthkit-queries skill**: For HealthKit data preparation and query patterns used in SwiftUI views
