# Phausto JUCE plugins: building the editor

Instructions for an LLM. They apply to any plugin exported by Phausto (Faust DSP in Pharo) that contains `Source/PhaustoParams.h`. Target: C++17, JUCE 7 or later. Read the whole file before writing code.

## 0. How to work

1. Read `Source/PhaustoParams.h` and `Source/PluginEditor.h` first. If you do not have them, ask the user to paste them. Use the parameter IDs and class names found there. Never guess them.
2. Edit only `PluginEditor.h`, `PluginEditor.cpp` and new headers next to them. The one processor exception is section 9.
3. Deliver complete files, not fragments.
4. After the code, list every parameter ID the UI binds.

## 1. How a Phausto export works

```text
Faust code in Pharo
        |  Phausto export
        v
PhaustoParams::table --createLayout()--> apvts (processor) --every audio block--> Faust DSP
                                           ^
                                           |  attachments
                                     editor widgets
```

All C++ is in `Source/`. Class names start with the plugin type: `Effect`, `MonoSynth` or `PolySynth`. The examples use `Effect`.

| File | Edit? | Contents |
|---|---|---|
| `PluginEditor.h/.cpp` | **Yes** | `EffectAudioProcessorEditor`, the UI. Holds `EffectAudioProcessor& audioProcessor` |
| `PhaustoParams.h` | No | Parameter table and APVTS layout, generated from the Faust JSON |
| `PluginProcessor.h/.cpp` | No (section 9 excepted) | `EffectAudioProcessor`. Owns the Faust DSP and a public `juce::AudioProcessorValueTreeState apvts` built from `PhaustoParams::createLayout()`. Copies the APVTS values into Faust every block, and saves and restores state through the APVTS |
| `Faust<Type>.h`, other generated files | No | The DSP compiled from Faust, helpers |
| `CMakeLists.txt` | Only to add a `.cpp` | Build definition |
| `build.cmake` | No | Build: run `cmake -P build.cmake` in the project folder |

What follows from this:

- Faust is the only source of parameters. The editor never creates, renames or re-ranges one. A new parameter means changing the Faust code and exporting again.
- The editor can bind exactly the rows of `PhaustoParams::table`. Faust bargraphs and soundfiles are not there, and neither are `freq`, `gate` and `gain` in synths (MIDI drives them).
- Automation, state saving and DSP updates already work. The editor only adds widgets and their attachments.
- IDs are Faust short names. Renaming a Faust control, or adding one with a clashing label, can change an ID. Re-read `PhaustoParams.h` after every export.
- Exporting again can overwrite the editor files. Keep them under version control.

## 2. `PhaustoParams.h`

```cpp
namespace PhaustoParams
{
    struct Descriptor {
        const char* id;           // APVTS parameter ID: the only key for binding
        const char* faustPath;    // Faust address, used by the processor only
        const char* label;        // display name
        float min, max, def, step;
        bool isToggle;            // true: juce::AudioParameterBool, false: juce::AudioParameterFloat
    };

    static const Descriptor table[] = { /* one row per parameter */ };
    static constexpr int count = /* number of rows */;

    inline juce::AudioProcessorValueTreeState::ParameterLayout createLayout();   // builds the APVTS from table
}
```

- Iterate `table` with a range-based `for` and use `count` for its size. Do not rely on `table` being a C array.
- `id`: pass it unchanged to an attachment. Never write an ID that is not in the table.
- `isToggle`: `true` binds a `juce::Button` through a `ButtonAttachment`, `false` binds a `juce::Slider` through a `SliderAttachment`.
- `min`, `max`, `step`, `def`: already in the parameter. The attachment copies range and value into the widget.
- `label`: display text, converted with `juce::String::fromUTF8 (d.label)`.
- `faustPath`: for the processor only.
- If the real header has more fields (a widget style, for example), use them.

## 3. Safety rules

Ownership

1. A component is a value member, a `std::unique_ptr` member, or an element of `std::vector<std::unique_ptr<juce::Component>>`. Allocate with `std::make_unique`. No owning raw pointers, no `new`, no `delete`. (The processor's `createEditor()` returns `new` because JUCE hands ownership to the host. Leave it.)
2. Declare each attachment after the widget it binds. Members are destroyed in reverse order, so the attachment goes first.
3. A `std::unique_ptr` member that must never be null is initialized in the constructor's initializer list and declared `const`.

Parameters

4. Bind only through attachments: `SliderAttachment`, `ButtonAttachment`, or `juce::ParameterAttachment` for custom components. They handle host gestures, automation and threading.
5. Before binding by ID, check `apvts.getParameter (id) != nullptr`. Never dereference an unchecked parameter pointer.
6. Never call `setRange`, `setNormalisableRange` or `setValue` on an attached slider, nor `setToggleState` on an attached button. Never write a parameter from `onValueChange`, `onClick` or `paint`.
7. Convert descriptor text with `juce::String::fromUTF8`: `juce::String (const char*)` asserts on non-ASCII text.

Threads

8. Editor code runs on the message thread only. Never touch a component from `processBlock`.
9. A callback that runs later (`juce::MessageManager::callAsync`, `juce::Timer::callAfterDelay`) captures `juce::Component::SafePointer<EffectAudioProcessorEditor> (this)` and checks it against `nullptr` before use. Never capture a bare `this`.

Construction and files

10. `setSize` is the last statement of the editor constructor: it calls `resized()`, which expects every component to exist.
11. No `static` or global components, attachments or LookAndFeels.
12. New classes go in headers next to `PluginEditor.h`. A new `.cpp` must be added to the plugin target's sources in `CMakeLists.txt` (or to the `.jucer` project when building with the Projucer).

## 4. Building blocks: `Source/ParameterControls.h`

Each class owns its widget and the widget's attachment, so the destruction order is fixed inside the class (RAII). `makeControl` is the only place that branches on the parameter kind (Simple Factory). It never returns null: a parameter missing from the APVTS becomes a `MissingControl` that draws a red placeholder (Null Object). Editor code then needs no null checks, and a wrong ID shows on screen.

```cpp
#pragma once
#include "PhaustoParams.h"

namespace PhaustoUI
{
    using APVTS = juce::AudioProcessorValueTreeState;

    /** A rotary slider and its label, bound to one float parameter. */
    class ParameterSlider final : public juce::Component
    {
    public:
        ParameterSlider (APVTS& state, const PhaustoParams::Descriptor& d)
            : attachment (state, d.id, slider)
        {
            label.setText (juce::String::fromUTF8 (d.label), juce::dontSendNotification);
            label.setJustificationType (juce::Justification::centred);
            slider.setSliderStyle (juce::Slider::RotaryHorizontalVerticalDrag);
            slider.setTextBoxStyle (juce::Slider::TextBoxBelow, false, 72, 18);
            addAndMakeVisible (label);
            addAndMakeVisible (slider);
        }

        void resized() override
        {
            auto area = getLocalBounds();
            label.setBounds (area.removeFromTop (20));
            slider.setBounds (area);
        }

    private:
        juce::Label label;
        juce::Slider slider;
        APVTS::SliderAttachment attachment;   // after slider: destroyed first

        JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (ParameterSlider)
    };

    /** A toggle button bound to one bool parameter. */
    class ParameterToggle final : public juce::Component
    {
    public:
        ParameterToggle (APVTS& state, const PhaustoParams::Descriptor& d)
            : attachment (state, d.id, button)
        {
            button.setButtonText (juce::String::fromUTF8 (d.label));
            addAndMakeVisible (button);
        }

        void resized() override
        {
            button.setBounds (getLocalBounds());
        }

    private:
        juce::ToggleButton button;
        APVTS::ButtonAttachment attachment;   // after button: destroyed first

        JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (ParameterToggle)
    };

    /** Stands in for a control whose parameter does not exist. */
    class MissingControl final : public juce::Component
    {
    public:
        explicit MissingControl (const juce::String& missingID) : id (missingID) {}

        void paint (juce::Graphics& g) override
        {
            g.setColour (juce::Colours::red);
            g.drawRect (getLocalBounds());
            g.drawFittedText ("missing: " + id, getLocalBounds().reduced (4),
                              juce::Justification::centred, 2);
        }

    private:
        juce::String id;

        JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (MissingControl)
    };

    /** Never returns null. */
    inline std::unique_ptr<juce::Component> makeControl (APVTS& state, const PhaustoParams::Descriptor& d)
    {
        if (state.getParameter (d.id) == nullptr)
        {
            jassertfalse;   // the table and the APVTS disagree
            return std::make_unique<MissingControl> (d.id);
        }

        if (d.isToggle)
            return std::make_unique<ParameterToggle> (state, d);

        return std::make_unique<ParameterSlider> (state, d);
    }
}
```

## 5. Editor A: one control per parameter

Works for any export unchanged. Complete files, replacing the generated editor.

`PluginEditor.h`:

```cpp
#pragma once
#include <JuceHeader.h>
#include "PluginProcessor.h"
#include "ParameterControls.h"

class EffectAudioProcessorEditor : public juce::AudioProcessorEditor
{
public:
    EffectAudioProcessorEditor (EffectAudioProcessor&);
    ~EffectAudioProcessorEditor() override;

    void paint (juce::Graphics&) override;
    void resized() override;

private:
    EffectAudioProcessor& audioProcessor;
    std::vector<std::unique_ptr<juce::Component>> controls;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (EffectAudioProcessorEditor)
};
```

`PluginEditor.cpp`:

```cpp
#include "PluginProcessor.h"
#include "PluginEditor.h"

namespace
{
    constexpr int columns    = 4;
    constexpr int cellWidth  = 112;
    constexpr int cellHeight = 132;
    constexpr int margin     = 6;
    constexpr int border     = 10;
}

EffectAudioProcessorEditor::EffectAudioProcessorEditor (EffectAudioProcessor& p)
    : AudioProcessorEditor (&p), audioProcessor (p)
{
    for (const auto& d : PhaustoParams::table)
    {
        controls.push_back (PhaustoUI::makeControl (audioProcessor.apvts, d));
        addAndMakeVisible (*controls.back());
    }

    const int rows = juce::jmax (1, (static_cast<int> (controls.size()) + columns - 1) / columns);
    setSize (columns * cellWidth + 2 * border, rows * cellHeight + 2 * border);   // last: calls resized()
}

EffectAudioProcessorEditor::~EffectAudioProcessorEditor() = default;

void EffectAudioProcessorEditor::paint (juce::Graphics& g)
{
    g.fillAll (getLookAndFeel().findColour (juce::ResizableWindow::backgroundColourId));
}

void EffectAudioProcessorEditor::resized()
{
    for (std::size_t i = 0; i < controls.size(); ++i)
    {
        const auto column = static_cast<int> (i) % columns;
        const auto row    = static_cast<int> (i) / columns;

        controls[i]->setBounds (juce::Rectangle<int> (cellWidth, cellHeight)
                                    .withPosition (border + column * cellWidth, border + row * cellHeight)
                                    .reduced (margin));
    }
}
```

## 6. Editor B: chosen parameters in chosen places

For a designed layout. The IDs are placeholders: copy the real ones from `PhaustoParams::table`. A wrong ID shows a red `MissingControl`, it does not crash.

In `PluginEditor.h`, replace the `controls` member of section 5 with:

```cpp
private:
    EffectAudioProcessor& audioProcessor;

    // created in the initializer list: never null, never reset
    const std::unique_ptr<juce::Component> cutoff;
    const std::unique_ptr<juce::Component> resonance;
```

`PluginEditor.cpp` (destructor and `paint` as in section 5):

```cpp
#include "PluginProcessor.h"
#include "PluginEditor.h"

namespace
{
    constexpr const char* cutoffID    = "Cutoff";      // placeholder
    constexpr const char* resonanceID = "Resonance";   // placeholder

    std::unique_ptr<juce::Component> makeControlFor (PhaustoUI::APVTS& state, const juce::String& id)
    {
        for (const auto& d : PhaustoParams::table)
            if (id == d.id)
                return PhaustoUI::makeControl (state, d);

        jassertfalse;   // id is not in PhaustoParams::table
        return std::make_unique<PhaustoUI::MissingControl> (id);
    }
}

EffectAudioProcessorEditor::EffectAudioProcessorEditor (EffectAudioProcessor& p)
    : AudioProcessorEditor (&p),
      audioProcessor (p),
      cutoff (makeControlFor (p.apvts, cutoffID)),
      resonance (makeControlFor (p.apvts, resonanceID))
{
    addAndMakeVisible (*cutoff);
    addAndMakeVisible (*resonance);
    setSize (400, 220);   // last: calls resized()
}

void EffectAudioProcessorEditor::resized()
{
    auto area = getLocalBounds().reduced (10);
    cutoff->setBounds (area.removeFromLeft (area.getWidth() / 2).reduced (5));
    resonance->setBounds (area.reduced (5));
}
```

## 7. Custom components

A widget that is not a `juce::Slider` or a `juce::Button` (an XY pad, a drawn control) binds through `juce::ParameterAttachment`:

- The attachment calls back on the message thread with the new value. Store it and `repaint()`.
- Report the user's gesture with `beginGesture()`, `setValueAsPartOfGesture (value)` and `endGesture()`, or with `setValueAsCompleteGesture (value)` for a single click. Hosts record automation from these calls.
- Values are in real units (denormalised). Map them for drawing with the parameter's `NormalisableRange`.
- Declare the attachments last: they are destroyed first, so no callback reaches a destroyed member.

`Source/XYPad.h`:

```cpp
#pragma once
#include <JuceHeader.h>

/** Two float parameters on one surface: x to the right, y upwards. */
class XYPad final : public juce::Component
{
public:
    XYPad (juce::RangedAudioParameter& xParam, juce::RangedAudioParameter& yParam)
        : xRange (xParam.getNormalisableRange()),
          yRange (yParam.getNormalisableRange()),
          xAttachment (xParam, [this] (float v) { x = v; repaint(); }),
          yAttachment (yParam, [this] (float v) { y = v; repaint(); })
    {
        xAttachment.sendInitialUpdate();
        yAttachment.sendInitialUpdate();
    }

    void paint (juce::Graphics& g) override
    {
        const auto area = getLocalBounds().toFloat();
        const juce::Point<float> dot { area.getX() + xRange.convertTo0to1 (x) * area.getWidth(),
                                       area.getBottom() - yRange.convertTo0to1 (y) * area.getHeight() };

        g.fillAll (juce::Colours::black);
        g.setColour (juce::Colours::orange);
        g.fillEllipse (juce::Rectangle<float> (12.0f, 12.0f).withCentre (dot));
    }

    void mouseDown (const juce::MouseEvent& e) override
    {
        xAttachment.beginGesture();
        yAttachment.beginGesture();
        mouseDrag (e);
    }

    void mouseDrag (const juce::MouseEvent& e) override
    {
        const auto area = getLocalBounds().toFloat();
        const auto nx = juce::jlimit (0.0f, 1.0f, (e.position.x - area.getX()) / area.getWidth());
        const auto ny = juce::jlimit (0.0f, 1.0f, (area.getBottom() - e.position.y) / area.getHeight());
        xAttachment.setValueAsPartOfGesture (xRange.convertFrom0to1 (nx));
        yAttachment.setValueAsPartOfGesture (yRange.convertFrom0to1 (ny));
    }

    void mouseUp (const juce::MouseEvent&) override
    {
        xAttachment.endGesture();
        yAttachment.endGesture();
    }

private:
    juce::NormalisableRange<float> xRange, yRange;
    float x = 0.0f, y = 0.0f;
    juce::ParameterAttachment xAttachment, yAttachment;   // last: destroyed first

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (XYPad)
};
```

In `PluginEditor.cpp`, include `"XYPad.h"` and add this factory to the anonymous namespace. It keeps the Null Object fallback:

```cpp
std::unique_ptr<juce::Component> makeXYPad (PhaustoUI::APVTS& state, const juce::String& xID, const juce::String& yID)
{
    auto* xParam = state.getParameter (xID);
    auto* yParam = state.getParameter (yID);

    if (xParam == nullptr || yParam == nullptr)
    {
        jassertfalse;
        return std::make_unique<PhaustoUI::MissingControl> (xParam == nullptr ? xID : yID);
    }

    return std::make_unique<XYPad> (*xParam, *yParam);
}
```

Hold the pad like any control: `const std::unique_ptr<juce::Component> pad;`, initialized with `makeXYPad (p.apvts, xID, yID)`.

## 8. Custom look

Restyle stock widgets with a `juce::LookAndFeel_V4` subclass (Strategy: the widget delegates its drawing). Drawing code reads only its arguments, never the processor or a parameter.

`Source/PluginLookAndFeel.h`:

```cpp
#pragma once
#include <JuceHeader.h>

class PluginLookAndFeel final : public juce::LookAndFeel_V4
{
public:
    void drawRotarySlider (juce::Graphics& g, int x, int y, int width, int height,
                           float sliderPos, float startAngle, float endAngle, juce::Slider&) override
    {
        const auto area   = juce::Rectangle<int> (x, y, width, height).toFloat().reduced (4.0f);
        const auto radius = juce::jmin (area.getWidth(), area.getHeight()) / 2.0f;
        const auto centre = area.getCentre();
        const auto angle  = startAngle + sliderPos * (endAngle - startAngle);

        g.setColour (juce::Colours::darkgrey);
        g.fillEllipse (juce::Rectangle<float> (2.0f * radius, 2.0f * radius).withCentre (centre));
        g.setColour (juce::Colours::orange);
        g.drawLine (juce::Line<float> (centre, centre.getPointOnCircumference (radius, angle)), 3.0f);
    }
};
```

In the editor:

```cpp
// PluginEditor.h, private: right after audioProcessor, so it outlives every component
PluginLookAndFeel lookAndFeel;
```

```cpp
// constructor body: after the children are added, before setSize
setLookAndFeel (&lookAndFeel);
```

```cpp
EffectAudioProcessorEditor::~EffectAudioProcessorEditor()
{
    setLookAndFeel (nullptr);
}
```

## 9. Visuals driven by audio (the only processor edit)

Meters and scopes need audio data, which parameters do not carry. Add one atomic to the processor: written on the audio thread, read by a timer on the message thread. No locks, no allocation and no `MessageManager` calls in `processBlock`. Exporting again regenerates the processor, so re-apply these two lines.

```cpp
// PluginProcessor.h, public:
std::atomic<float> outputLevel { 0.0f };

// PluginProcessor.cpp, last statement of processBlock:
outputLevel.store (buffer.getMagnitude (0, buffer.getNumSamples()), std::memory_order_relaxed);
```

`Source/LevelMeter.h`:

```cpp
#pragma once
#include <JuceHeader.h>

class LevelMeter final : public juce::Component, private juce::Timer
{
public:
    explicit LevelMeter (const std::atomic<float>& source) : level (source)
    {
        startTimerHz (30);
    }

    void paint (juce::Graphics& g) override
    {
        const auto fraction = std::isfinite (shown) ? juce::jlimit (0.0f, 1.0f, shown) : 0.0f;
        g.setColour (juce::Colours::limegreen);
        g.fillRect (getLocalBounds().toFloat().withWidth (fraction * static_cast<float> (getWidth())));
    }

private:
    void timerCallback() override
    {
        shown = level.load (std::memory_order_relaxed);
        repaint();
    }

    const std::atomic<float>& level;   // owned by the processor, which outlives the editor
    float shown = 0.0f;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (LevelMeter)
};
```

In the editor: `LevelMeter meter { audioProcessor.outputLevel };`, declared after `audioProcessor`.

## 10. Known limits

- Ranges are linear: Faust `[scale:log]` and `[unit:...]` metadata are not exported.
- Faust bargraphs are not parameters. Show audio-driven values with section 9.
- When an ID changes (section 1), hosts lose saved values and automation for that parameter.

## 11. Check before answering

- Every ID comes from `PhaustoParams.h`.
- Every attachment is declared after its widget.
- No `new`, no `delete`, no owning raw pointer.
- No generated file edited, except the section 9 lines.
- `setSize` is last in the constructor. If the constructor calls `setLookAndFeel`, the destructor calls `setLookAndFeel (nullptr)`.
