# Artful plugin blueprint

Custom, animated JUCE editor controls for plugins exported by Phausto, bound to any number of APVTS parameters with two lines in the editor. Written as context for people and for LLM assistants.

**Status, 26 October 2026.** The lightning XY pad was built and played in the FilteronSK plugin, bound by a two-parameter `XYPadAttachment`. The kit below is the same code generalized to N parameters. It has not been built yet.

## For assistants: the short version

- Phausto generates `PluginProcessor.h/.cpp`, `PhaustoParams.h`, `CMakeLists.txt` and `build.cmake`. Leave them alone. You write header-only controls in `Source/` and a few editor lines.
- A control derives from `jubloc::ProportionControl`: it edits N values in 0..1 and knows no parameter.
- `jubloc::ProportionAttachment` binds a control to N parameter ids, one per proportion, in index order. Nothing else touches the APVTS.
- In gesture code: `moveProportion (index, value)` while the mouse is down, `endGesture()` in `mouseUp`.
- `paint` is a pure function of state. Randomness and geometry are computed in mouse or timer handlers, then stored.
- Ranges, curves and smoothing live in Faust. Controls map their geometry to 0..1 linearly.
- C++17, JUCE 8.0.4, `namespace jubloc`, `juce::` qualified names, JUCE code style, no em dashes in comments.

## The stack

| Piece | Made by | Contract |
|---|---|---|
| Faust DSP | you, in Phausto | the single source of truth for parameters: names, ranges, steps, defaults |
| `Source/PhaustoParams.h` | Phausto | `table[i].id` are the APVTS parameter ids (Faust shortnames, sorted by Faust address) |
| `Source/PluginProcessor.h/.cpp` | Phausto | owns a public `apvts`; `processBlock` pushes every APVTS value into Faust once per block |
| `Source/PluginEditor.h/.cpp` | Phausto skeleton, then you | holds the controls and their attachments |
| `CMakeLists.txt`, `build.cmake` | Phausto | fetches JUCE 8.0.4 (or uses `JUCE_PATH`); header-only additions need no CMake change |
| the kit and your controls | you | header-only, in `Source/` |

Class names follow the plugin type: an effect exports `EffectAudioProcessor` and `EffectAudioProcessorEditor`.

## Architecture

```
Faust DSP -> APVTS parameters <-> ParameterLink (one per parameter) <-> ProportionAttachment <-> your ProportionControl
```

| Class | Role | Pattern, and why |
|---|---|---|
| `ProportionControl` | base Component editing N values in 0..1 | like a `juce::Slider` with several values and no range: the art never sees parameter ranges |
| `ParameterLink` | one parameter seen as a 0..1 proportion | Adapter over `juce::ParameterAttachment`: range, skew and step stay in the APVTS |
| `ProportionAttachment` | binds a control to N parameter ids | Mediator, as JUCE's `SliderParameterAttachment`: the control stays reusable and testable |
| `onProportionChange`, `onGestureEnd` | the control's callbacks | Null Object: no-op lambdas by default, so they are called without a test |
| `Strike` (in the reference control) | how the art evolves | Value Object: each transition answers a new value, so the control keeps no flags |
| `LightningBolt` (same) | pure shape generator | static utility class, like `juce::Decibels` |

### What the kit guarantees

- **Gestures per parameter.** A `ParameterLink` opens its gesture on its first move and closes it at the gesture end. A drag that moves only some proportions leaves the automation of the other parameters untouched in Touch and Latch modes.
- **RAII close.** A link closes its open gesture when destroyed, so closing the editor mid-drag never leaves the host waiting for the end of a gesture.
- **Release safety.** A missing id, or one id too few or too many, asserts in Debug and leaves the control unbound in Release (as JUCE's own attachments do), instead of dereferencing null inside the host.
- **No dangling lambdas.** The attachment resets the control's callbacks in its destructor.
- **Threads.** Host automation reaches the control through `juce::ParameterAttachment`, already on the message thread, where paint, mouse and timer code also run.
- **State recall.** Each link sends an initial update, so a reopened editor shows the current values.

## Rules

1. Controls never include `juce_audio_processors` and never hold a parameter id. Only the attachment does.
2. Declare proportion indices in an `enum Proportions { ..., numProportions }`. The attachment takes the ids in that order.
3. Each parameter id belongs to one attachment only.
4. In gesture code, call `moveProportion`, never `setProportion` (the attachment side, which calls no callback). End every gesture in `mouseUp` with `endGesture()`.
5. `paint` reads state and draws. It never draws random numbers or advances an animation.
6. Animation uses `private juce::Timer`: start it on interaction, stop it when the art is idle, and call `stopTimer()` first in the destructor.
7. In the editor, declare each control and then its attachment, after `audioProcessor`. C++ builds members top down and destroys them bottom up, so the attachment lets go first.
8. Every class is non-copyable (`JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR`). No raw `new`, no unchecked lookup.

## Faust side

- **Ids** are Faust shortnames. Renaming a control in Faust renames its id, and the attachment's `jassert` reports the stale id in a Debug build.
- **Curves and ranges** belong in Faust: the exporter ignores `[scale:log]` for now, and controls stay linear.
- **Smoothing.** Put `si.smoo` on every parameter a gesture drives. APVTS values reach Faust once per block, so fast drags zipper otherwise.
- **Buttons and checkboxes** become bool parameters. As a proportion they snap to 0 or 1, and Faust buttons latch (the APVTS has no momentary type).

## House style

- JUCE formatting: Allman braces, a space before the parentheses of a call with arguments (`setColour (id, colour)`), none for an empty call (`repaint()`).
- Qualify JUCE names with `juce::`. Do not rely on the `using namespace juce` in `JuceHeader.h`.
- `#pragma once`, module includes (`<juce_gui_basics/juce_gui_basics.h>`), header-only, `namespace jubloc`.
- Small classes with one job each, polymorphism over conditionals, the pattern named in a comment when one is used, comments that say why rather than what.
- No em dashes in comments or prose.

## The kit

Copy these three headers into `Source/` unchanged.

### `ParameterLink.h`

```cpp
#pragma once
#include <juce_audio_processors/juce_audio_processors.h>

namespace jubloc
{

// Adapter: juce::ParameterAttachment speaks parameter values, a ProportionControl speaks 0..1.
// convertTo0to1 and convertFrom0to1 apply the APVTS range, skew and step, so the musical
// mapping stays where the parameter is defined: in Faust.
class ParameterLink
{
public:
    ParameterLink (juce::RangedAudioParameter& parameterToUse, std::function<void (float)> onProportion)
        : parameter (parameterToUse),
          attachment (parameterToUse,
                      [this, onProportion] (float value) { onProportion (parameter.convertTo0to1 (value)); })
    {}

    // RAII: an editor closed mid-drag still closes the gesture it opened.
    ~ParameterLink() { endGesture(); }

    // The gesture opens on the first move, so a drag that moves only some proportions
    // leaves the automation of the other parameters untouched (Touch and Latch modes).
    void setProportion (float newProportion)
    {
        if (! gestureOpen)
            attachment.beginGesture();

        gestureOpen = true;
        attachment.setValueAsPartOfGesture (parameter.convertFrom0to1 (newProportion));
    }

    void endGesture()
    {
        if (gestureOpen)
            attachment.endGesture();

        gestureOpen = false;
    }

    void sendInitialUpdate() { attachment.sendInitialUpdate(); }

private:
    juce::RangedAudioParameter& parameter;
    juce::ParameterAttachment attachment;
    bool gestureOpen = false;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (ParameterLink)
};

} // namespace jubloc
```

### `ProportionControl.h`

```cpp
#pragma once
#include <juce_gui_basics/juce_gui_basics.h>

namespace jubloc
{

// A Component that edits N values in 0..1, like a juce::Slider with several values and no range.
// It knows no parameter: ProportionAttachment binds index i to the i-th parameter id it is given.
// Subclasses draw, handle the mouse, and report through moveProportion and endGesture.
class ProportionControl : public juce::Component
{
public:
    // No-op by default (Null Object), so they are called without a test.
    std::function<void (int)> onProportionChange = [] (int) {};
    std::function<void()> onGestureEnd = [] {};

    int getNumProportions() const noexcept { return (int) proportions.size(); }

    float getProportion (int index) const
    {
        return isProportionIndex (index) ? proportions[(size_t) index] : 0.0f;
    }

    // Attachment side (host automation, state recall): shows the value, calls no callback.
    void setProportion (int index, float newProportion)
    {
        if (! isProportionIndex (index))
            return;

        proportions[(size_t) index] = newProportion;
        repaint();
    }

protected:
    explicit ProportionControl (int numProportions)
        : proportions ((size_t) numProportions, 0.0f)
    {}

    // Gesture side, for subclasses: move values while the mouse is down, end the gesture in mouseUp.
    void moveProportion (int index, float newProportion)
    {
        if (! isProportionIndex (index))
            return;

        proportions[(size_t) index] = juce::jlimit (0.0f, 1.0f, newProportion);
        repaint();
        onProportionChange (index);
    }

    void endGesture() { onGestureEnd(); }

private:
    bool isProportionIndex (int index) const
    {
        const auto valid = juce::isPositiveAndBelow (index, getNumProportions());
        jassert (valid); // an index the subclass did not declare
        return valid;
    }

    std::vector<float> proportions;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (ProportionControl)
};

} // namespace jubloc
```

### `ProportionAttachment.h`

```cpp
#pragma once
#include "ParameterLink.h"
#include "ProportionControl.h"

namespace jubloc
{

// Mediator between a ProportionControl and one APVTS parameter per proportion, in index order,
// as juce::SliderParameterAttachment is for one slider and one parameter.
class ProportionAttachment
{
public:
    ProportionAttachment (juce::AudioProcessorValueTreeState& apvts,
                          const juce::StringArray& parameterIDs,
                          ProportionControl& controlToUse)
        : control (controlToUse)
    {
        const auto parameters = findParameters (apvts, parameterIDs);

        for (size_t i = 0; i < parameters.size(); ++i)
            links.push_back (std::make_unique<ParameterLink> (*parameters[i],
                [this, index = (int) i] (float proportion) { control.setProportion (index, proportion); }));

        if (links.empty())
            return; // unbound: the control keeps its no-op callbacks

        control.onProportionChange = [this] (int index)
        {
            links[(size_t) index]->setProportion (control.getProportion (index));
        };

        control.onGestureEnd = [this]
        {
            for (auto& link : links)
                link->endGesture();
        };

        for (auto& link : links)
            link->sendInitialUpdate();
    }

    ~ProportionAttachment()
    {
        // The control outlives this object: leave it no lambda pointing here.
        // The links close any gesture still open as they are destroyed.
        control.onProportionChange = [] (int) {};
        control.onGestureEnd = [] {};
    }

private:
    // Every id resolved and one per proportion, or nothing at all. As JUCE's own attachments,
    // a mistake asserts in Debug and leaves the control unbound in Release, rather than
    // dereferencing null inside the host.
    std::vector<juce::RangedAudioParameter*> findParameters (juce::AudioProcessorValueTreeState& apvts,
                                                             const juce::StringArray& parameterIDs) const
    {
        std::vector<juce::RangedAudioParameter*> found;

        for (const auto& id : parameterIDs)
            found.push_back (apvts.getParameter (id));

        const auto allFound = std::find (found.begin(), found.end(), nullptr) == found.end();
        const auto onePerProportion = (int) found.size() == control.getNumProportions();

        if (allFound && onePerProportion)
            return found;

        jassertfalse; // ids must be rows of PhaustoParams::table, one per proportion, in index order
        return {};
    }

    ProportionControl& control;
    std::vector<std::unique_ptr<ParameterLink>> links;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (ProportionAttachment)
};

} // namespace jubloc
```

## Reference control: the lightning XY pad

X drives the Korg35 cutoff, Y its resonance. A bolt strikes from the top edge to the touch point, crackles while held and fades in under half a second after release.

### `LightningBolt.h`

```cpp
#pragma once
#include <juce_graphics/juce_graphics.h>

namespace jubloc
{

// Midpoint displacement: each pass splits every segment and pushes its new midpoint
// sideways by up to the current offset, then halves the offset. Static only, like juce::Decibels.
class LightningBolt
{
    using Points = std::vector<juce::Point<float>>;

public:
    LightningBolt() = delete;

    static juce::Path between (juce::Point<float> from, juce::Point<float> to, juce::Random& random)
    {
        Points points { from, to };
        auto offset = from.getDistanceFrom (to) / 4.0f;

        for (int pass = 0; pass < passes; ++pass)
        {
            points = split (points, offset, random);
            offset /= 2.0f;
        }

        return pathThrough (points);
    }

private:
    static constexpr int passes = 5; // 33 points

    static Points split (const Points& points, float offset, juce::Random& random)
    {
        Points result { points.front() };

        for (size_t i = 1; i < points.size(); ++i)
        {
            const auto a = points[i - 1];
            const auto b = points[i];
            const auto push = (random.nextFloat() * 2.0f - 1.0f) * offset;

            result.push_back ((a + b) / 2.0f + unitNormal (b - a) * push);
            result.push_back (b);
        }

        return result;
    }

    // The unit vector at 90 degrees, or zero for a zero-length segment.
    static juce::Point<float> unitNormal (juce::Point<float> v)
    {
        const auto length = v.getDistanceFromOrigin();
        return length > 0.0f ? juce::Point<float> { -v.y, v.x } / length : juce::Point<float>();
    }

    static juce::Path pathThrough (const Points& points)
    {
        juce::Path path;
        path.startNewSubPath (points.front());

        for (size_t i = 1; i < points.size(); ++i)
            path.lineTo (points[i]);

        return path;
    }
};

} // namespace jubloc
```

### `Strike.h`

```cpp
#pragma once
#include "LightningBolt.h"

namespace jubloc
{

// Value Object: a Strike changes only by answering a new one, so the pad keeps one field and no flags.
// Held: decay 1, so each tick draws a new bolt (the crackle) at full brightness.
// Released: each tick keeps 75 % of the brightness (the fade). Default constructed: spent.
class Strike
{
public:
    Strike() = default;

    static Strike at (juce::Point<float> point, juce::Random& random)
    {
        return { point, boltTo (point, random), 1.0f, 1.0f };
    }

    Strike released() const                    { return { target, bolt, brightness, releaseDecay }; }
    Strike ticked (juce::Random& random) const { return { target, boltTo (target, random), brightness * decay, decay }; }
    bool isSpent() const noexcept              { return brightness < spentBrightness; }

    // Widest and faintest first: a glow without a blur. Then the flash where it lands.
    void paint (juce::Graphics& g, juce::Colour halo, juce::Colour core) const
    {
        if (isSpent())
            return;

        stroke (g, 12.0f, halo.withAlpha (0.12f * brightness));
        stroke (g, 5.0f,  halo.withAlpha (0.45f * brightness));
        stroke (g, 1.5f,  core.withAlpha (brightness));
        flash  (g, 28.0f, halo.withAlpha (0.15f * brightness));
        flash  (g, 10.0f, core.withAlpha (0.8f * brightness));
    }

private:
    static constexpr float releaseDecay = 0.75f;     // dark after 14 frames: under half a second at 30 Hz
    static constexpr float spentBrightness = 0.02f;

    Strike (juce::Point<float> targetToUse, juce::Path boltToUse, float brightnessToUse, float decayToUse)
        : target (targetToUse), bolt (std::move (boltToUse)), brightness (brightnessToUse), decay (decayToUse)
    {}

    // From the top edge, straight above the point.
    static juce::Path boltTo (juce::Point<float> point, juce::Random& random)
    {
        return LightningBolt::between ({ point.x, 0.0f }, point, random);
    }

    void stroke (juce::Graphics& g, float thickness, juce::Colour colour) const
    {
        g.setColour (colour);
        g.strokePath (bolt, juce::PathStrokeType (thickness, juce::PathStrokeType::curved,
                                                  juce::PathStrokeType::rounded));
    }

    void flash (juce::Graphics& g, float radius, juce::Colour colour) const
    {
        g.setColour (colour);
        g.fillEllipse (juce::Rectangle<float> (2.0f * radius, 2.0f * radius).withCentre (target));
    }

    juce::Point<float> target;
    juce::Path bolt;
    float brightness = 0.0f, decay = 0.0f;
};

} // namespace jubloc
```

### `XYPad.h`

```cpp
#pragma once
#include "ProportionControl.h"
#include "Strike.h"

namespace jubloc
{

// A Kaoss-style pad: two proportions, y growing upward, a bolt where you touch.
class XYPad : public ProportionControl,
              private juce::Timer
{
public:
    // Proportion indices. The attachment takes one parameter id per index, in this order.
    enum Proportions { horizontal, vertical, numProportions };

    enum ColourIds
    {
        backgroundColourId = 0x4a790001,
        haloColourId,
        coreColourId
    };

    XYPad()
        : ProportionControl (numProportions)
    {
        setOpaque (true);
        setColour (backgroundColourId, juce::Colour (0xff0b0d1a));
        setColour (haloColourId, juce::Colour (0xff7f5cff));
        setColour (coreColourId, juce::Colours::white);
    }

    ~XYPad() override
    {
        stopTimer(); // before any member is destroyed
    }

    void paint (juce::Graphics& g) override
    {
        g.fillAll (findColour (backgroundColourId));
        g.setColour (findColour (coreColourId).withAlpha (0.6f));
        g.fillEllipse (juce::Rectangle<float> (8.0f, 8.0f).withCentre (pointAt (currentProportions())));
        strike.paint (g, findColour (haloColourId), findColour (coreColourId));
    }

    void mouseDown (const juce::MouseEvent& e) override
    {
        strikeAt (e.position);
        startTimerHz (frameRate);
    }

    void mouseDrag (const juce::MouseEvent& e) override
    {
        strikeAt (e.position);
    }

    void mouseUp (const juce::MouseEvent&) override
    {
        strike = strike.released();
        endGesture();
    }

private:
    static constexpr int frameRate = 30;

    void strikeAt (juce::Point<float> position)
    {
        const auto target = proportionAt (position);
        strike = Strike::at (pointAt (target), random);
        moveProportion (horizontal, target.x);
        moveProportion (vertical, target.y);
    }

    // Each frame: a new bolt, and less brightness once released. Stops when dark.
    void timerCallback() override
    {
        strike = strike.ticked (random);

        if (strike.isSpent())
            stopTimer();

        repaint();
    }

    juce::Point<float> currentProportions() const
    {
        return { getProportion (horizontal), getProportion (vertical) };
    }

    juce::Point<float> proportionAt (juce::Point<float> position) const
    {
        return { juce::jlimit (0.0f, 1.0f, position.x / (float) getWidth()),
                 juce::jlimit (0.0f, 1.0f, 1.0f - position.y / (float) getHeight()) };
    }

    juce::Point<float> pointAt (juce::Point<float> proportion) const
    {
        return { proportion.x * (float) getWidth(), (1.0f - proportion.y) * (float) getHeight() };
    }

    Strike strike;
    juce::Random random;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (XYPad)
};

} // namespace jubloc
```

### Editor wiring

`PluginEditor.h`

```cpp
#pragma once

#include <JuceHeader.h>
#include "PluginProcessor.h"
#include "XYPad.h"
#include "ProportionAttachment.h"

class EffectAudioProcessorEditor : public juce::AudioProcessorEditor
{
public:
    explicit EffectAudioProcessorEditor (EffectAudioProcessor&);
    ~EffectAudioProcessorEditor() override = default;

    void paint (juce::Graphics&) override;
    void resized() override;

private:
    EffectAudioProcessor& audioProcessor;

    // After audioProcessor, each control before its attachment: built top down, destroyed bottom up.
    jubloc::XYPad pad;
    jubloc::ProportionAttachment padAttachment { audioProcessor.apvts, { "Korg35LPFFr", "Korg35LPFRes" }, pad };

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (EffectAudioProcessorEditor)
};
```

`PluginEditor.cpp`

```cpp
#include "PluginProcessor.h"
#include "PluginEditor.h"

EffectAudioProcessorEditor::EffectAudioProcessorEditor (EffectAudioProcessor& p)
    : AudioProcessorEditor (&p), audioProcessor (p)
{
    addAndMakeVisible (pad);
    setSize (400, 400);
}

void EffectAudioProcessorEditor::paint (juce::Graphics&)
{
    // Nothing: the controls are opaque and cover the editor.
}

void EffectAudioProcessorEditor::resized()
{
    pad.setBounds (getLocalBounds());
}
```

## More parameters

Nothing in the kit changes with the count: a control declares how many proportions it has, and the attachment takes that many ids. This second control gives each of K stars two proportions, so it drives 2K parameters.

### `Constellation.h`

```cpp
#pragma once
#include "ProportionControl.h"

namespace jubloc
{

// Stars joined by faint lines, two proportions each: x at index 2k, y at 2k + 1, y growing upward.
// A drag moves the nearest star only, so the host writes automation for that star's two
// parameters and leaves the others alone.
class Constellation : public ProportionControl
{
public:
    explicit Constellation (int numStars)
        : ProportionControl (2 * numStars)
    {
        jassert (numStars > 0);
        setOpaque (true);
    }

    static constexpr int xIndex (int star) noexcept { return 2 * star; }
    static constexpr int yIndex (int star) noexcept { return 2 * star + 1; }

    void paint (juce::Graphics& g) override
    {
        g.fillAll (juce::Colour (0xff05060d));

        juce::Path lines;
        lines.startNewSubPath (pointOf (0));

        for (int star = 1; star < getNumStars(); ++star)
            lines.lineTo (pointOf (star));

        g.setColour (juce::Colours::white.withAlpha (0.25f));
        g.strokePath (lines, juce::PathStrokeType (1.0f));

        g.setColour (juce::Colours::white);

        for (int star = 0; star < getNumStars(); ++star)
            g.fillEllipse (juce::Rectangle<float> (6.0f, 6.0f).withCentre (pointOf (star)));
    }

    void mouseDown (const juce::MouseEvent& e) override
    {
        grabbed = nearestStarTo (e.position);
        moveGrabbedStarTo (e.position);
    }

    void mouseDrag (const juce::MouseEvent& e) override
    {
        moveGrabbedStarTo (e.position);
    }

    void mouseUp (const juce::MouseEvent&) override
    {
        endGesture();
    }

private:
    int getNumStars() const noexcept { return getNumProportions() / 2; }

    juce::Point<float> pointOf (int star) const
    {
        return { getProportion (xIndex (star)) * (float) getWidth(),
                 (1.0f - getProportion (yIndex (star))) * (float) getHeight() };
    }

    int nearestStarTo (juce::Point<float> position) const
    {
        auto nearest = 0;

        for (int star = 1; star < getNumStars(); ++star)
            if (pointOf (star).getDistanceFrom (position) < pointOf (nearest).getDistanceFrom (position))
                nearest = star;

        return nearest;
    }

    void moveGrabbedStarTo (juce::Point<float> position)
    {
        moveProportion (xIndex (grabbed), position.x / (float) getWidth());
        moveProportion (yIndex (grabbed), 1.0f - position.y / (float) getHeight());
    }

    int grabbed = 0;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (Constellation)
};

} // namespace jubloc
```

### Several controls in one editor

One member pair per control, laid out in `resized()`. The ids below are examples: use the ones in your `PhaustoParams.h`.

```cpp
// PluginEditor.h, private:
EffectAudioProcessor& audioProcessor;

jubloc::XYPad pad;
jubloc::ProportionAttachment padAttachment { audioProcessor.apvts, { "Cutoff", "Resonance" }, pad };

jubloc::Constellation stars { 3 };
jubloc::ProportionAttachment starsAttachment { audioProcessor.apvts,
                                               { "Star1X", "Star1Y", "Star2X", "Star2Y", "Star3X", "Star3Y" },
                                               stars };
```

```cpp
// PluginEditor.cpp
EffectAudioProcessorEditor::EffectAudioProcessorEditor (EffectAudioProcessor& p)
    : AudioProcessorEditor (&p), audioProcessor (p)
{
    addAndMakeVisible (pad);
    addAndMakeVisible (stars);
    setSize (800, 400);
}

void EffectAudioProcessorEditor::resized()
{
    auto area = getLocalBounds();
    pad.setBounds (area.removeFromLeft (area.getWidth() / 2));
    stars.setBounds (area);
}
```

## Recipe for a new artful plugin

1. Write the DSP in Phausto, with `si.smoo` on every parameter a gesture will drive, and export it with the skeleton editor. Read the ids in `Source/PhaustoParams.h`.
2. Copy the kit into `Source/`.
3. Write the control: derive from `ProportionControl` (and from `private juce::Timer` if it animates), declare `enum Proportions`, draw in `paint`, call `moveProportion` from `mouseDown` and `mouseDrag`, and `endGesture()` from `mouseUp`.
4. Keep the art in small helpers: Value Objects for evolving state, static classes for geometry, `ColourIds` for colours.
5. In the editor: the control and its attachment after `audioProcessor`, `addAndMakeVisible`, bounds in `resized()`, `setSize`. Optionally `setResizable (true, true)`: every control maps through proportions, so it scales.
6. Build with `cmake -P build.cmake`.
7. Check in a host: a drag records automation for the moved parameters only, automation playback moves the art, and a reopened editor shows the current values.

## Build and debug

```sh
cmake -P build.cmake 2>&1 | grep -A3 "error:" | head -40   # only the errors
grep -n "^class" Source/*.h                                  # one class per header, named after its file
```

Fix the first error only: the rest usually cascade from it.

| First error | Cause | Fix |
|---|---|---|
| `extraneous closing brace`, then `unknown type name` for one of your classes | a header holds another header's code, or a partial paste | check with the `grep` above, then re-paste the whole file |
| `unknown type name 'EffectAudioProcessor'` | the editor names differ from `PluginProcessor.h` | use the names Phausto generated |
| `definition of explicitly defaulted destructor` | the header defaults it and the `.cpp` defines it too | keep one |
| `use of undeclared identifier 'controls'` (or `labels`) | the generic editor body is still in the `.cpp` | use the skeleton body |
| `'apvts' is a private member` | the processor hides it | make it public |
| `cannot initialize object parameter of type 'juce::Component'` in the editor | cascade: a member type failed, so the editor stopped being a Component | fix the first error |
| warning `private field '...' is not used`, next to errors | cascade: the code using the field failed to compile | fix the first error |

## Testing

Value Objects and geometry are pure, so they test without a window, with Catch2 as Phausto's exporter tests do. For example: a held `Strike` never becomes spent, a released one is spent within 15 ticks, and `ProportionControl` clamps a moved value to 0..1.

## Prompt template

```text
Context: the attached artful-plugin-blueprint.md.
Task: write jubloc::<Name>, a header-only ProportionControl.
Parameter ids from PhaustoParams::table, in proportion index order: <id>, <id>, ...
Look: <what it draws>.
Gesture: <how the mouse moves which proportions>.
Animation: <none, or what evolves and when it stops>.
Follow the Rules and the House style. Give each new header in full, then the editor lines.
```

## Not covered yet

- **Audio-reactive visuals.** Art that follows the sound needs values written by `processBlock` (for example a `std::atomic<float>` level) and read in the control's timer. The generated processor exposes none yet, and Phausto keeps Faust bargraphs out of the APVTS.
- **Text.** Value readouts, labels, text entry.
- **Theming and accessibility.** A LookAndFeel for the controls, accessibility handlers.
- **JuBloc.** Mirroring these controls in Pharo/Bloc and generating the editor lines belongs to the JuBloc export work.

## FilteronSK

Built with `XYPadAttachment`, the two-parameter special case of this kit. To move it onto the kit: add the three kit headers, replace `XYPad.h` with the one above, delete `XYPadAttachment.h`, and change the attachment line in `PluginEditor.h` to the `ProportionAttachment` one. `LightningBolt.h` and `Strike.h` stay as they are.
