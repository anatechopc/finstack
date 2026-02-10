# Design System

This document describes the design tokens, patterns, and conventions used throughout the Loooans app.

## Color Palette

All colors are defined in `AppColors` (`lib/utils/screen_helpers.dart`).

### Primary Colors

| Name       | Hex       | Usage                                          |
|------------|-----------|------------------------------------------------|
| `green1`   | `#38DC93` | Primary brand, scaffold background, app bar    |
| `green1_5` | `#28A16B` | Darker green variant                           |
| `green1_6` | `#16A163` | Darkest green variant                          |
| `green2`   | `#92E50A` | Accent, loan item cards                        |

### Semantic Colors

| Name                         | Hex       | Usage                                   |
|------------------------------|-----------|-----------------------------------------|
| `red`                        | `#FE5858` | Error states, validation errors         |
| `red2`                       | `#E51C1C` | Secondary error/warning                 |
| `blue`                       | `#299CFF` | Information states, loan items          |
| `white`                      | `#FFFFFF` | Backgrounds, text on dark surfaces      |
| `black`                      | `#000000` | Primary text, button backgrounds        |
| `lightBlack`                 | `#1C1B1F` | Secondary text, dropdown backgrounds    |
| `buttonIconTransparencyBlack`| `#0D000000` | Button icon transparency overlay      |
| `ubOrange`                   | `#FEA30B` | Secondary accent                        |

### Chart Colors

| Name         | Hex       | Usage                          |
|--------------|-----------|--------------------------------|
| `chart1`     | `#BB86FC` | Purple - charts, capital usage |
| `chart1_1`   | `#BB86FC` | Purple variant - sales charts  |
| `chart2`     | `#FFC775` | Orange - charts                |
| `chart2_1`   | `#FFDF80` | Light orange - sales charts    |
| `chart3`     | `#EE77A2` | Pink/Magenta - charts          |
| `chart4`     | `#D582E3` | Purple/Magenta - charts        |
| `chart5`     | `#FCBB86` | Light orange - charts          |
| `chart6`     | `#80CBC3` | Teal - charts, loan items      |
| `chartEmpty` | `#404040` | Empty state in charts          |

### Color Lists

```dart
// Loan item backgrounds cycle through these colors
loanItemColorsList = [green2, blue, chart6, chart2]

// Capital usage pie/donut charts
capitalUsageItemColorsList = [chart1, chart2, chart3, chart4, chart5, chart6]

// Sales charts
salesItemColorsList = [chart1_1, chart2_1, chart3, chart4, chart5, chart6]
```

---

## Typography

**Font Family:** Google Fonts - [Urbanist](https://fonts.google.com/specimen/Urbanist)

### Font Sizes

| Size  | Constant             | Usage                                    |
|-------|----------------------|------------------------------------------|
| 64px  | `displayLarge`       | Logo title                               |
| 24px  | `headlineLarge`      | Section headers, dialog titles           |
| 20px  | `headlineMedium`     | Amount displays (whole number)           |
| 18px  | `titleLarge`         | Tagline/subtitle                         |
| 16px  | `bodyLarge`          | Body text, welcome text, buttons         |
| 14px  | `bodyMedium`         | Card titles, notification text           |
| 12px  | `bodySmall`          | Helper text, chips, currency symbols     |
| 10px  | `labelSmall`         | Timestamps, tertiary text                |

### Font Weights

| Weight | Usage                                    |
|--------|------------------------------------------|
| w600   | Headers, titles, amounts, emphasis       |
| w500   | Labels, medium emphasis                  |
| w400   | Body text (default)                      |
| w300   | Currency symbols, decimals, de-emphasized|

### Typography Constants

Defined in `AppTypography` (`lib/utils/screen_helpers.dart`):

```dart
AppTypography.displayLarge   // 64.0
AppTypography.headlineLarge  // 24.0
AppTypography.headlineMedium // 20.0
AppTypography.titleLarge     // 18.0
AppTypography.bodyLarge      // 16.0
AppTypography.bodyMedium     // 14.0
AppTypography.bodySmall      // 12.0
AppTypography.labelSmall     // 10.0
```

---

## Spacing

### Core Spacing Constants

Defined in `lib/utils/screen_helpers.dart`:

| Constant            | Value   | Usage                    |
|---------------------|---------|--------------------------|
| `defaultPaddingSize`| 16.0    | Standard padding         |
| `defaultRadiusSize` | 16.0    | Standard border radius   |
| `defaultIconSize`   | 24.0    | Icon dimensions          |

### Semantic Spacing

Defined in `AppSpacing` (`lib/utils/screen_helpers.dart`):

```dart
AppSpacing.xs   // 4.0  - Extra small
AppSpacing.sm   // 8.0  - Small
AppSpacing.md   // 16.0 - Medium (default)
AppSpacing.lg   // 24.0 - Large
AppSpacing.xl   // 32.0 - Extra large
AppSpacing.xxl  // 48.0 - Extra extra large
```

### Button Padding

| Constant                    | Value                      | Usage                |
|-----------------------------|----------------------------|----------------------|
| `defaultButtonPadding`      | `vertical: 24, horizontal: 20` | Standard buttons |
| `defaultCompactButtonPadding`| `vertical: 16, horizontal: 24` | Compact buttons  |
| `defaultIconButtonPadding`  | `vertical: 18, horizontal: 20` | Buttons with icons |

---

## Border Radius

| Constant            | Value  | Usage                          |
|---------------------|--------|--------------------------------|
| `defaultBorderRadius`| 16.0  | Buttons, cards, inputs         |
| 32.0                | -      | Chips, avatars (pill shape)    |
| Circle              | -      | Avatars, badges                |

```dart
// Pre-built radius objects
defaultRadius = Radius.circular(16.0)
defaultBorderRadius = BorderRadius.circular(16.0)
```

---

## Screen Breakpoints

Based on [Material 3 Layout Guidelines](https://m3.material.io/foundations/layout/applying-layout/window-size-classes).

| Size       | Width      | Devices                              |
|------------|------------|--------------------------------------|
| `compact`  | < 600px    | Phones                               |
| `medium`   | 600-840px  | Tablet portrait, phone landscape     |
| `expanded` | 840-1200px | Tablet landscape, small desktop      |
| `large`    | >= 1200px  | Desktop                              |

### Layout Constants

| Constant                     | Value   | Usage                           |
|------------------------------|---------|---------------------------------|
| `largeScreenDetailBreakPoint`| 1500px  | Detail pane visibility threshold|
| `detailContainerSize`        | 500px   | Fixed detail container width    |

### Usage

```dart
final screenSize = getScreenSize(context: context);

switch (screenSize) {
  case ScreenSize.compact:
    // Phone layout
    break;
  case ScreenSize.medium:
    // Tablet portrait layout
    break;
  case ScreenSize.expanded:
    // Tablet landscape / small desktop
    break;
  case ScreenSize.large:
    // Full desktop layout
    break;
}
```

---

## Component Patterns

### Buttons

#### Filled Button (Primary Action)

```dart
ButtonWidgets.defaultFilledButton(
  onPressed: () {},
  child: Text('Submit'),
  // Defaults:
  // backgroundColor: AppColors.black
  // foregroundColor: AppColors.white
  // padding: defaultButtonPadding
  // borderRadius: 16
)
```

#### Outlined Button (Secondary Action)

```dart
ButtonWidgets.defaultOutlinedButton(
  onPressed: () {},
  child: Text('Cancel'),
  // Defaults:
  // foregroundColor: AppColors.black
  // padding: defaultButtonPadding
  // borderRadius: 16
)
```

### Form Inputs

All form inputs use consistent decoration:

```dart
FormWidgets.defaultFormBuilderTextField(
  name: 'fieldName',
  label: 'Field Label',
  // Defaults:
  // contentPadding: EdgeInsets.all(16)
  // borderRadius: defaultBorderRadius (16)
  // borderColor: AppColors.black
  // errorColor: AppColors.red
  // floatingLabelBehavior: FloatingLabelBehavior.always
)
```

**Input Border States:**
- **Enabled/Focused:** `borderColor` (default black)
- **Disabled:** `borderColor.withOpacity(0.6)`
- **Error/Focused Error:** `AppColors.red`

### Dialogs

```dart
AlertDialog(
  backgroundColor: AppColors.green1,
  title: Text('Title'),
  content: Text('Content'),
  actions: [
    ButtonWidgets.defaultOutlinedButton(...),
    ButtonWidgets.defaultFilledButton(...),
  ],
)
```

**Dialog Defaults:**
- Background: `AppColors.green1`
- Content padding: `EdgeInsets.all(24)`
- Shape: `RoundedRectangleBorder` with `defaultBorderRadius`

### Cards

```dart
Card(
  color: AppColors.white,
  shape: RoundedRectangleBorder(
    borderRadius: defaultBorderRadius,
  ),
  child: Padding(
    padding: EdgeInsets.all(defaultPaddingSize),
    child: content,
  ),
)
```

### Chips

Chips use a pill (stadium) shape:

```dart
Chip(
  label: Text('Label'),
  shape: StadiumBorder(),
  padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
)
```

### Loading Indicator

```dart
CircularProgressIndicator(
  color: AppColors.green1,
)
```

---

## Theme Configuration

The app theme is defined in `lib/app/theme.dart` using `buildAppTheme()`.

### Key Theme Properties

- **Scaffold Background:** `AppColors.green1`
- **App Bar Background:** `AppColors.green1`
- **Text Color:** `AppColors.black`
- **Font Family:** Urbanist (via Google Fonts)

### Color Scheme

```dart
ColorScheme(
  primary: AppColors.green1,
  secondary: AppColors.green2,
  error: AppColors.red,
  surface: AppColors.white,
  onPrimary: AppColors.black,
  onSecondary: AppColors.black,
  onError: AppColors.white,
  onSurface: AppColors.black,
)
```

---

## Accessibility Notes

- **Text Scaling:** App applies `TextScaler.linear(1.2)` globally for improved readability
- **Contrast:** Primary green (`#38DC93`) with black text meets WCAG AA for large text
- **Touch Targets:** Buttons use generous padding for accessible tap targets

---

## File References

| File | Contents |
|------|----------|
| `lib/utils/screen_helpers.dart` | `AppColors`, `AppSpacing`, `AppTypography`, spacing constants |
| `lib/app/theme.dart` | `buildAppTheme()` function |
| `lib/widgets/button_widgets.dart` | `ButtonWidgets` class |
| `lib/widgets/form_widgets.dart` | `FormWidgets` class |
| `lib/widgets/dialog_widgets.dart` | `DialogWidgets` class |
