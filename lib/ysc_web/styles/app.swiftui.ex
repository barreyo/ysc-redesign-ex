defmodule YscWeb.Styles.App.SwiftUI do
  use LiveViewNative.Stylesheet, :swiftui

  # Add your styles here
  # Refer to your client's documentation on what the proper syntax
  # is for defining rules within classes
  ~SHEET"""
  "kiosk-screen" do
    frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    padding(56)
  end

  "kiosk-screen-leading" do
    frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    padding(48)
  end

  "kiosk-stack-560" do
    frame(maxWidth: 560)
  end

  "kiosk-stack-720" do
    frame(maxWidth: 720)
  end

  "kiosk-stack-900" do
    frame(maxWidth: 900)
  end

  "kiosk-stack-980" do
    frame(maxWidth: 980)
  end

  "kiosk-card" do
    padding(20)
    background(Color(.secondarySystemBackground))
    clipShape(RoundedRectangle(cornerRadius: 16))
  end

  "kiosk-card-lg" do
    padding(30)
    background(Color(.secondarySystemBackground))
    clipShape(RoundedRectangle(cornerRadius: 20))
  end

  "kiosk-primary-button" do
    buttonStyle(.borderedProminent)
    controlSize(.large)
  end

  "kiosk-secondary-button" do
    buttonStyle(.bordered)
    controlSize(.large)
  end

  "kiosk-primary-button-wide" do
    buttonStyle(.borderedProminent)
    controlSize(.large)
    frame(minWidth: 520)
  end

  "kiosk-primary-button-full" do
    buttonStyle(.borderedProminent)
    controlSize(.large)
    frame(maxWidth: .infinity)
  end

  "kiosk-secondary-button-full" do
    buttonStyle(.bordered)
    controlSize(.large)
    frame(maxWidth: .infinity)
  end

  "kiosk-textfield" do
    textFieldStyle(.roundedBorder)
    textInputAutocapitalization(.characters)
    autocorrectionDisabled()
    frame(height: 56)
  end

  "kiosk-textfield-52" do
    textFieldStyle(.roundedBorder)
    textInputAutocapitalization(.characters)
    autocorrectionDisabled()
    frame(height: 52)
  end

  "kiosk-chip" do
    buttonStyle(.bordered)
    controlSize(.large)
  end

  "kiosk-chip-selected" do
    buttonStyle(.borderedProminent)
    controlSize(.large)
  end

  "kiosk-checkmark" do
    font(.system(size: 88))
    foregroundStyle(.green)
  end

  "main-logo" do
    resizable()
    scaledToFit()
    frame(maxWidth: 240, maxHeight: 120)
  end

  "image-fail" do
    foregroundStyle(.secondary)
    frame(width: 44, height: 44)
  end
  """

  # If you need to have greater control over how your style rules are created
  # you can use the function defintion style which is more verbose but allows
  # for more fine-grained controled
  #
  # This example shows what is not possible within the more concise ~SHEET
  # use `<Text class="frame:w100:h200" />` allows for a setting
  # of both the `width` and `height` values.

  # def class("frame:" <> dims) do
  #   [width] = Regex.run(~r/w(\d+)/, dims, capture: :all_but_first)
  #   [height] = Regex.run(~r/h(\d+)/, dims, capture: :all_but_first)

  #   ~RULES"""
  #   frame(width: {width}, height: {height})
  #   """
  # end
end
