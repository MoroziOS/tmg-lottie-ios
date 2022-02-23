// Created by Cal Stephens on 1/13/22.
// Copyright © 2022 Airbnb Inc. All rights reserved.

import QuartzCore

// MARK: - ValueProviderStore

/// Registration and storage for `AnyValueProvider`s that can dynamically
/// provide custom values for `AnimationKeypath`s within an `Animation`.
final class ValueProviderStore {

  // MARK: Internal

  /// Registers an `AnyValueProvider` for the given `AnimationKeypath`
  func setValueProvider(_ valueProvider: AnyValueProvider, keypath: AnimationKeypath) {
    LottieLogger.shared.assert(
      valueProvider.typeErasedStorage.isSupportedByCoreAnimationRenderingEngine,
      """
      The Core Animation rendering engine doesn't support Value Providers that vend a closure,
      because that would require calling the closure on the main thread once per frame.
      """)

    // TODO: Support more value types
    LottieLogger.shared.assert(
      keypath.keys.last == PropertyName.color.rawValue,
      "The new rendering engine currently only supports customizing color values")

    valueProviders.append((keypath: keypath, valueProvider: valueProvider))
  }

  // Retrieves the custom value keyframes for the given property,
  // if an `AnyValueProvider` was registered for the given keypath.
  func customKeyframes<Value>(
    of customizableProperty: CustomizableProperty<Value>,
    for keypath: AnimationKeypath)
    -> KeyframeGroup<Value>?
  {
    guard let anyValueProvider = valueProvider(for: keypath) else {
      return nil
    }

    // Retrieve the type-erased keyframes from the custom `ValueProvider`
    let typeErasedKeyframes: [Keyframe<Any>]
    switch anyValueProvider.typeErasedStorage {
    case .singleValue(let typeErasedValue):
      typeErasedKeyframes = [Keyframe(typeErasedValue)]

    case .keyframes(let keyframes, _):
      typeErasedKeyframes = keyframes

    case .closure:
      LottieLogger.shared.assertionFailure("""
        The Core Animation rendering engine doesn't support Value Providers that vend a closure,
        because that would require calling the closure on the main thread once per frame.
        """)
      return nil
    }

    // Convert the type-erased keyframe values using this `CustomizableProperty`'s conversion closure
    let typedKeyframes = typeErasedKeyframes.compactMap { typeErasedKeyframe -> Keyframe<Value>? in
      guard let convertedValue = customizableProperty.conversion(typeErasedKeyframe.value) else {
        LottieLogger.shared.assertionFailure("""
          Could not convert value of type \(type(of: typeErasedKeyframe.value)) to expected type \(Value.self)
          """)
        return nil
      }

      return typeErasedKeyframe.withValue(convertedValue)
    }

    // Verify that all of the keyframes were successfully converted to the expected type
    guard typedKeyframes.count == typeErasedKeyframes.count else {
      return nil
    }

    return KeyframeGroup(keyframes: ContiguousArray(typedKeyframes))
  }

  // MARK: Private

  private var valueProviders = [(keypath: AnimationKeypath, valueProvider: AnyValueProvider)]()

  /// Retrieves the most-recently-registered Value Provider that matches the given keypat
  private func valueProvider(for keypath: AnimationKeypath) -> AnyValueProvider? {
    // Find the last keypath matching the given keypath,
    // so we return the value provider that was registered most-recently
    valueProviders.last(where: { registeredKeypath, _ in
      keypath.matches(registeredKeypath)
    })?.valueProvider
  }

}

extension AnyValueProviderStorage {
  /// Whether or not this type of value provider is supported
  /// by the new Core Animation rendering engine
  var isSupportedByCoreAnimationRenderingEngine: Bool {
    switch self {
    case .singleValue, .keyframes:
      return true
    case .closure:
      return false
    }
  }
}

extension AnimationKeypath {
  /// Whether or not this keypath from the animation hierarchy
  /// matches the given keypath (which may contain wildcards)
  func matches(_ keypath: AnimationKeypath) -> Bool {
    var regex = "^" // match the start of the string
      + keypath.keys.joined(separator: "\\.") // match this keypath, escaping "." characters
      + "$" // match the end of the string

    // ** wildcards match anything
    //  - "**.Color" matches both "Layer 1.Color" and "Layer 1.Layer 2.Color"
    regex = regex.replacingOccurrences(of: "**", with: ".+")

    // * wildcards match any individual path component
    //  - "*.Color" matches "Layer 1.Color" but not "Layer 1.Layer 2.Color"
    regex = regex.replacingOccurrences(of: "*", with: "[^.]+")

    return fullPath.range(of: regex, options: .regularExpression) != nil
  }
}
