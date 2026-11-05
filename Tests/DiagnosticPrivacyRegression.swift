import Foundation
@main struct DiagnosticPrivacyRegression {
 static func main() {
  precondition(!DiagnosticPrivacy.redacted("{\"Authorization\": \"Bearer UNSAFE\"}").contains("UNSAFE"))
  precondition(!DiagnosticPrivacy.redacted("https://example.org/path?%70assword=UNSAFE#token=UNSAFE").contains("UNSAFE"))
  precondition(!DiagnosticPrivacy.redacted("Authorization: Bearer UNSAFE\nnext line").contains("UNSAFE"))
  precondition(!DiagnosticPrivacy.redacted("Set-Cookie: session=UNSAFE").contains("UNSAFE"))
  precondition(!DiagnosticPrivacy.redacted("https://user:UNSAFE@example.org/x").contains("UNSAFE"))
  precondition(!DiagnosticPrivacy.redacted("{\"token\":\"UNSAFE value\", \"password\": \"UNSAFE\"}").contains("UNSAFE"))
  precondition(!DiagnosticPrivacy.redacted("<session_id>UNSAFE</session_id>").contains("UNSAFE"))
  precondition(!DiagnosticPrivacy.redacted("api_key=UNSAFE&mode=FT8").contains("UNSAFE"))
  precondition(DiagnosticPrivacy.redacted("Radio: timeout (code -1001)") == "Radio: timeout (code -1001)")
  precondition(!DiagnosticPrivacy.redacted("line\r\nforged\u{0000}entry").contains("\n"))
  precondition(DiagnosticPrivacy.redacted(String(repeating: "x", count: 65537)).contains("omitted"))
  print("Diagnostic privacy regression passed")
 }
}
