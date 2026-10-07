import Foundation

enum Links {
    static let jiraToken = URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens")!
    static let kakaoPaySupport = "https://qr.kakaopay.com/FTnV4mPBD"
    /// 맥에서는 카카오페이 링크가 열리지 않아, QR 이미지 페이지를 연다(휴대폰으로 스캔).
    static let kakaoPaySupportQR = URL(string: "https://api.qrserver.com/v1/create-qr-code/?size=360x360&margin=16&data=https%3A%2F%2Fqr.kakaopay.com%2FFTnV4mPBD")!
}
