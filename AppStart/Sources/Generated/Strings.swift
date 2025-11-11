// swiftlint:disable all
// Generated using SwiftGen — https://github.com/SwiftGen/SwiftGen

import Foundation

// swiftlint:disable superfluous_disable_command file_length implicit_return prefer_self_in_static_references

// MARK: - Strings

// swiftlint:disable explicit_type_interface function_parameter_count identifier_name line_length
// swiftlint:disable nesting type_body_length type_name vertical_whitespace_opening_braces
internal enum L10n {
  /// Latest
  internal static let stringLatest = L10n.tr("Localizable", "string_latest", fallback: "Latest")
  /// Log Details
  internal static let stringLogDetails = L10n.tr("Localizable", "string_log_details", fallback: "Log Details")
  /// Log List
  internal static let stringLogList = L10n.tr("Localizable", "string_log_list", fallback: "Log List")
  /// Request was cancelled.
  internal static let stringNetCancelled = L10n.tr("Localizable", "string_net_cancelled", fallback: "Request was cancelled.")
  /// Unable to connect to the server. Please try again later.
  internal static let stringNetConnectFailed = L10n.tr("Localizable", "string_net_connect_failed", fallback: "Unable to connect to the server. Please try again later.")
  /// Data parsing failed. Please try again later.
  internal static let stringNetDecodingError = L10n.tr("Localizable", "string_net_decoding_error", fallback: "Data parsing failed. Please try again later.")
  /// Request data error. Please try again later.
  internal static let stringNetEncodingError = L10n.tr("Localizable", "string_net_encoding_error", fallback: "Request data error. Please try again later.")
  /// You do not have permission to perform this action.
  internal static let stringNetForbidden = L10n.tr("Localizable", "string_net_forbidden", fallback: "You do not have permission to perform this action.")
  /// Request failed, please try again later.
  internal static let stringNetHttpError = L10n.tr("Localizable", "string_net_http_error", fallback: "Request failed, please try again later.")
  /// The requested resource was not found.
  internal static let stringNetNotFound = L10n.tr("Localizable", "string_net_not_found", fallback: "The requested resource was not found.")
  /// Server error, please try again later.
  internal static let stringNetServerError = L10n.tr("Localizable", "string_net_server_error", fallback: "Server error, please try again later.")
  /// Untrusted network environment. Please switch networks and try again.
  internal static let stringNetSslUntrusted = L10n.tr("Localizable", "string_net_ssl_untrusted", fallback: "Untrusted network environment. Please switch networks and try again.")
  /// Request timed out. Please try again later.
  internal static let stringNetTimeout = L10n.tr("Localizable", "string_net_timeout", fallback: "Request timed out. Please try again later.")
  /// Session expired. Please log in again.
  internal static let stringNetUnauthorized = L10n.tr("Localizable", "string_net_unauthorized", fallback: "Session expired. Please log in again.")
  /// Network unavailable. Please check your connection.
  internal static let stringNetUnavailable = L10n.tr("Localizable", "string_net_unavailable", fallback: "Network unavailable. Please check your connection.")
  /// An unknown error occurred. Please try again later.
  internal static let stringNetUnknown = L10n.tr("Localizable", "string_net_unknown", fallback: "An unknown error occurred. Please try again later.")
}
// swiftlint:enable explicit_type_interface function_parameter_count identifier_name line_length
// swiftlint:enable nesting type_body_length type_name vertical_whitespace_opening_braces

// MARK: - Implementation Details

extension L10n {
  private static func tr(_ table: String, _ key: String, _ args: CVarArg..., fallback value: String) -> String {
    let format = BundleToken.bundle.localizedString(forKey: key, value: value, table: table)
    return String(format: format, locale: Locale.current, arguments: args)
  }
}

// swiftlint:disable convenience_type
private final class BundleToken {
  static let bundle: Bundle = {
    #if SWIFT_PACKAGE
    return Bundle.module
    #else
    return Bundle(for: BundleToken.self)
    #endif
  }()
}
// swiftlint:enable convenience_type
