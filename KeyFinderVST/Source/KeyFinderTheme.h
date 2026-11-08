#pragma once

#include <JuceHeader.h>

// Mirrors the desktop app's Dark theme (Sources/KeyFinder/Models/ThemeManager.swift) so the
// plug-in and the app read as one product.
namespace KeyFinderTheme
{
    inline const juce::Colour background   = juce::Colour::fromFloatRGBA (0.035f, 0.03f, 0.05f, 1.0f);
    inline const juce::Colour text         = juce::Colour::fromFloatRGBA (0.95f, 0.95f, 0.95f, 1.0f);
    inline const juce::Colour secondary    = text.withAlpha (0.75f);
    inline const juce::Colour tertiary     = text.withAlpha (0.60f);
    inline const juce::Colour surface      = text.withAlpha (0.06f);
    inline const juce::Colour border       = text.withAlpha (0.22f);
    inline const juce::Colour accent       = juce::Colour::fromFloatRGBA (0.72f, 0.55f, 0.98f, 1.0f);
    inline const juce::Colour accentSubtle = accent.withAlpha (0.22f);

    // Same per-number hue as the app's KF.camelotColor, so 4A reads indigo in both.
    inline juce::Colour camelotColour (const juce::String& camelot)
    {
        const int number = camelot.dropLastCharacters (1).getIntValue();
        if (number < 1 || number > 12)
            return juce::Colour (0xff999999);
        const float hue = std::fmod (float (number - 1) / 12.0f + 0.42f, 1.0f);
        return juce::Colour::fromHSV (hue, 0.55f, 1.0f, 1.0f);
    }

    inline juce::Font sans (float size, bool bold = false)
    {
        return juce::Font (juce::FontOptions (size, bold ? juce::Font::bold : juce::Font::plain));
    }

    // The app uses the system monospaced face; Menlo is its closest bundled match in JUCE.
    inline juce::Font mono (float size, bool bold = false)
    {
        return juce::Font (juce::FontOptions (juce::Font::getDefaultMonospacedFontName(), size,
                                              bold ? juce::Font::bold : juce::Font::plain));
    }

    class LookAndFeel : public juce::LookAndFeel_V4
    {
    public:
        LookAndFeel()
        {
            setColour (juce::ResizableWindow::backgroundColourId, background);
            setColour (juce::TextButton::buttonColourId, juce::Colours::transparentBlack);
            setColour (juce::TextButton::buttonOnColourId, accentSubtle);
            setColour (juce::TextButton::textColourOffId, secondary);
            setColour (juce::TextButton::textColourOnId, text);
            setColour (juce::Label::textColourId, text);
            setColour (juce::ComboBox::backgroundColourId, surface);
            setColour (juce::ComboBox::textColourId, text);
            setColour (juce::ComboBox::outlineColourId, border);
            setColour (juce::ComboBox::arrowColourId, secondary);
            setColour (juce::PopupMenu::backgroundColourId, background);
            setColour (juce::PopupMenu::textColourId, text);
            setColour (juce::PopupMenu::highlightedBackgroundColourId, accentSubtle);
            setColour (juce::PopupMenu::highlightedTextColourId, text);
        }

        void drawButtonBackground (juce::Graphics& g, juce::Button& button, const juce::Colour&,
                                   bool highlighted, bool down) override
        {
            const auto bounds = button.getLocalBounds().toFloat().reduced (0.5f);
            auto fill = button.getToggleState() ? accentSubtle : button.findColour (juce::TextButton::buttonColourId);
            if (button.isEnabled() && (highlighted || down))
                fill = fill.isTransparent() ? surface : fill.brighter (0.15f);
            if (! button.isEnabled())
                fill = fill.withMultipliedAlpha (0.3f);
            g.setColour (fill);
            g.fillRoundedRectangle (bounds, 6.0f);
            if (! button.getToggleState() && ! button.getProperties()["borderless"])
            {
                g.setColour (border);
                g.drawRoundedRectangle (bounds, 6.0f, 1.0f);
            }
        }

        juce::Font getTextButtonFont (juce::TextButton&, int buttonHeight) override
        {
            return mono (juce::jlimit (11.0f, 14.0f, buttonHeight * 0.42f), true);
        }

        void drawButtonText (juce::Graphics& g, juce::TextButton& button, bool, bool) override
        {
            g.setFont (getTextButtonFont (button, button.getHeight()));
            const auto colour = button.getToggleState() ? text
                              : button.findColour (juce::TextButton::textColourOffId);
            g.setColour (button.isEnabled() ? colour : colour.withAlpha (0.4f));
            g.drawFittedText (button.getButtonText(), button.getLocalBounds().reduced (4, 0),
                              juce::Justification::centred, 1, 1.0f);
        }

        juce::Font getComboBoxFont (juce::ComboBox&) override { return mono (12.0f); }
        juce::Font getPopupMenuFont() override { return mono (12.0f); }
    };
}
