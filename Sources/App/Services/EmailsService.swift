import Foundation
import Vapor
import Fluent
import FluentPostgresDriver

extension Application.Services {
    struct EmailsServiceKey: StorageKey {
        typealias Value = EmailsServiceType
    }

    var emailsService: EmailsServiceType {
        get {
            self.application.storage[EmailsServiceKey.self] ?? EmailsService()
        }
        nonmutating set {
            self.application.storage[EmailsServiceKey.self] = newValue
        }
    }
}

protocol EmailsServiceType {
    func sendForgotPasswordEmail(on request: Request, user: User) throws -> EventLoopFuture<Bool>
    func sendConfirmAccountEmail(on request: Request, user: User) throws -> EventLoopFuture<Bool>
}

final class EmailsService: EmailsServiceType {

    func sendForgotPasswordEmail(on request: Request, user: User) throws -> EventLoopFuture<Bool> {

        guard let emailServiceAddress = request.application.settings.configuration.emailServiceAddress else {
            throw Abort(.internalServerError, reason: "Email service is not configured in database.")
        }

        guard let forgotPasswordGuid = user.forgotPasswordGuid else {
            throw ForgotPasswordError.tokenNotGenerated
        }

        let userName = user.getUserName()

        let emailServiceUri = URI(string: "\(emailServiceAddress)/emails")
        let requestFuture = request.client.post(emailServiceUri) { httpRequest in
            let emailAddress = EmailAddressDto(address: user.email, name: user.name)
            let email = EmailDto(to: emailAddress,
                                title: "Letterer - Forgot password",
                                body: "<html><body><div>Hi \(userName),</div><div>You can reset your password by clicking following <a href='https://letterer.me/reset-password?token=\(forgotPasswordGuid)'>link</a>.</div></body></html>")

            try httpRequest.content.encode(email)
        }
        
        return requestFuture.map { _ in
            return true
        }
    }
    
    func sendConfirmAccountEmail(on request: Request, user: User) throws -> EventLoopFuture<Bool> {

        guard let emailServiceAddress = request.application.settings.configuration.emailServiceAddress else {
            throw Abort(.internalServerError, reason: "Email service is not configured in database.")
        }

        guard let userId = user.id else {
            throw RegisterError.userIdNotExists
        }

        let userName = user.getUserName()

        let emailServiceUri = URI(string: "\(emailServiceAddress)/emails")
        let requestFuture = request.client.post(emailServiceUri) { httpRequest in
            let emailAddress = EmailAddressDto(address: user.email, name: user.name)
            let email = EmailDto(to: emailAddress,
                                title: "Letterer - Confirm email",
                                body: "<html><body><div>Hi \(userName),</div><div>Please confirm your account by clicking following <a href='https://letterer.me/confirm-email?token=\(user.emailConfirmationGuid)&user=\(userId)'>link</a>.</div></body></html>")

            try httpRequest.content.encode(email)
        }
        
        return requestFuture.map { _ in
            return true
        }
    }
}
