//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@_spi(RawSyntax) import SwiftSyntax

// MARK: Lookahead

/// After calling `consume(ifAnyFrom:)` we know which token we are positioned
/// at based on that function's return type. This handle allows consuming that
/// token.
@_spi(RawSyntax)
public struct RecoveryConsumptionHandle {
  var unexpectedTokens: Int
  var tokenConsumptionHandle: TokenConsumptionHandle

  static func constant(_ spec: TokenSpec) -> RecoveryConsumptionHandle {
    return RecoveryConsumptionHandle(
      unexpectedTokens: 0,
      tokenConsumptionHandle: TokenConsumptionHandle(spec: spec)
    )
  }

  /// A `RecoveryConsumptionHandle` that will not eat any tokens but instead
  /// synthesize a missing token of kind `token`.
  static func missing(_ spec: TokenSpec) -> RecoveryConsumptionHandle {
    return RecoveryConsumptionHandle(
      unexpectedTokens: 0,
      tokenConsumptionHandle: TokenConsumptionHandle(spec: spec, missing: true)
    )
  }
}

extension Parser.Lookahead {
  /// See `canRecoverTo` that takes 3 specs.
  mutating func canRecoverTo(
    _ spec: TokenSpec
  ) -> RecoveryConsumptionHandle? {
    return canRecoverTo(spec, spec, spec)
  }

  /// See `canRecoverTo` that takes 3 specs.
  mutating func canRecoverTo(
    _ spec1: TokenSpec,
    _ spec2: TokenSpec
  ) -> RecoveryConsumptionHandle? {
    return canRecoverTo(spec1, spec2, spec1)
  }

  /// Tries eating tokens until it finds a token that matches `spec1`, `spec2` or `spec3`
  /// without skipping tokens that have a precedence that's higher than the
  /// lowest precedence in the expected kinds. If it found a token in this way,
  /// returns `true`, otherwise `false`.
  /// If this method returns `true`, the parser probably wants to consume the
  /// tokens this lookahead skipped over to find `kind` by consuming
  /// `lookahead.tokensConsumed` as unexpected.
  mutating func canRecoverTo(
    _ spec1: TokenSpec,
    _ spec2: TokenSpec,
    _ spec3: TokenSpec
  ) -> RecoveryConsumptionHandle? {
    let initialTokensConsumed = self.tokensConsumed

    let recoveryPrecedence = min(spec1.recoveryPrecedence, spec2.recoveryPrecedence, spec3.recoveryPrecedence)

    while !self.at(.eof) {
      if !recoveryPrecedence.shouldSkipOverNewlines, self.currentToken.isAtStartOfLine {
        break
      }
      let matchedSpec: TokenSpec?
      switch self.currentToken {
      case spec1:
        matchedSpec = spec1
      case spec2:
        matchedSpec = spec2
      case spec3:
        matchedSpec = spec3
      default:
        matchedSpec = nil
      }
      if let matchedSpec = matchedSpec {
        return RecoveryConsumptionHandle(
          unexpectedTokens: self.tokensConsumed - initialTokensConsumed,
          tokenConsumptionHandle: TokenConsumptionHandle(spec: matchedSpec)
        )
      }
      let currentTokenPrecedence = TokenPrecedence(self.currentToken.rawTokenKind)
      if currentTokenPrecedence >= recoveryPrecedence {
        break
      }
      self.consumeAnyToken()
      if let closingDelimiter = currentTokenPrecedence.closingTokenKind {
        let closingDelimiterSpec = TokenSpec(closingDelimiter)
        guard self.canRecoverTo(closingDelimiterSpec) != nil else {
          break
        }
        self.eat(closingDelimiterSpec)
      }
    }

    return nil
  }

  /// Checks if we can reach a token in `subset` by skipping tokens that have
  /// a precedence that have a lower ``TokenPrecedence`` than the minimum
  /// precedence of a token in that subset.
  /// If so, return the token that we can recover to and a handle that can be
  /// used to consume the unexpected tokens and the token we recovered to.
  mutating func canRecoverTo<SpecSet: TokenSpecSet>(
    anyIn specSet: SpecSet.Type,
    overrideRecoveryPrecedence: TokenPrecedence? = nil
  ) -> (match: SpecSet, handle: RecoveryConsumptionHandle)? {
    let initialTokensConsumed = self.tokensConsumed

    assert(!specSet.allCases.isEmpty, "SpecSet must have at least one case")
    let recoveryPrecedence =
      overrideRecoveryPrecedence ?? specSet.allCases.map({
        return $0.spec.recoveryPrecedence
      }).min()!
    var loopProgress = LoopProgressCondition()
    while !self.at(.eof) && loopProgress.evaluate(self.currentToken) {
      if !recoveryPrecedence.shouldSkipOverNewlines,
        self.currentToken.isAtStartOfLine
      {
        break
      }
      if let (kind, handle) = self.at(anyIn: specSet) {
        return (
          kind,
          RecoveryConsumptionHandle(
            unexpectedTokens: self.tokensConsumed - initialTokensConsumed,
            tokenConsumptionHandle: handle
          )
        )
      }
      let currentTokenPrecedence = TokenPrecedence(self.currentToken.rawTokenKind)
      if currentTokenPrecedence >= recoveryPrecedence {
        break
      }
      self.consumeAnyToken()
      if let closingDelimiter = currentTokenPrecedence.closingTokenKind {
        let closingDelimiterSpec = TokenSpec(closingDelimiter)
        guard self.canRecoverTo(closingDelimiterSpec) != nil else {
          break
        }
        self.eat(closingDelimiterSpec)
      }
    }

    return nil
  }
}
