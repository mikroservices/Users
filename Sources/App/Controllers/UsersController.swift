//
//  UsersController.swift
//  Letterer/Users
//
//  Created by Marcin Czachurski on 25/10/2018.
//

import Foundation
import Vapor
import JWT
import FluentSQLite
import Crypto
import Recaptcha

/// Controls basic operations for User object.
final class UsersController: RouteCollection {

    func boot(router: Router) throws {
        router.get("/users", UUID.parameter, use: profile)
        router.post(SignInRequestDto.self, at: "/users/login", use: login)
        router.post(UserDto.self, at: "/users", use: register)
        router.post(ConfirmEmailRequestDto.self, at: "/users/confirm", use: confirm)
    }

    /// User profile.
    func profile(request: Request) throws -> Future<UserDto> {

        let userIdFromParameter = try request.parameters.next(UUID.self)

        return User.find(userIdFromParameter, on: request).map(to: UserDto.self) { userFromDb in

            guard let user = userFromDb else {
                throw Abort(.badRequest, reason: "User with id '\(userIdFromParameter)' not exists.")
            }

            let userDto = UserDto(from: user)

            let userIdFromToken = try self.getUserIdFromBearerToken(request: request)
            let isProfileOwner = userIdFromToken == userIdFromParameter

            if !isProfileOwner {
                userDto.email = ""
            }

            return userDto
        }
    }

    // Register new user.
    func register(request: Request, userDto: UserDto) throws -> Future<UserDto> {

        guard let captchaToken = userDto.securityToken else {
            throw Abort(.badRequest, reason: "Security token is mandatory.")
        }

        guard let password = userDto.password else {
            throw Abort(.badRequest, reason: "Password is required.")
        }

        let captcha = try request.make(Captcha.self)
        return try captcha.validate(captchaFormResponse: captchaToken).flatMap(to: UserDto.self) { success in
        
            if !success {
                throw Abort(.badRequest, reason: "Security token is invalid.")
            }

            return User.query(on: request).filter(\.email == userDto.email).first().flatMap(to: User.self) { user in

                if user != nil {
                    throw Abort(.badRequest, reason: "User with email '\(userDto.email)' exists.")
                }

                let salt = try Password.generateSalt()
                let passwordHash = try Password.hash(password, withSalt: salt)
                let emailConfirmationGuid = UUID.init().uuidString

                let user = User(from: userDto, 
                                withPassword: passwordHash, 
                                salt: salt, 
                                emailConfirmationGuid: emailConfirmationGuid)

                return user.save(on: request)

            }.map(to: UserDto.self) { user in
                return UserDto(from: user)
            }
        }
    }

    /// Sign-in user.
    func login(request: Request, signInRequestDto: SignInRequestDto) throws -> Future<SignInResponseDto> {
        return User.query(on: request).filter(\.email == signInRequestDto.email).first().map(to: SignInResponseDto.self) { userFromDb in

            guard let user = userFromDb else {
                throw Abort(.unauthorized, reason: "Invalid email or password.")
            }

            let passwordHash = try Password.hash(signInRequestDto.password, withSalt: user.salt)
            if user.password != passwordHash {
                throw Abort(.unauthorized, reason: "Invalid email or password.")
            }

            if !user.emailWasConfirmed {
                throw Abort(.unauthorized, reason: "User email was not confirmed.")
            }

            if user.isBlocked {
                throw Abort(.unauthorized, reason: "User account is blocked.")
            }

            // Create payload.
            let accessToken = try self.createAccessToken(request: request, forUser: user)
            return SignInResponseDto(accessToken)
        }
    }

    /// Confirm email address.
    func confirm(request: Request, confirmEmailRequestDto: ConfirmEmailRequestDto) throws -> Future<HTTPResponseStatus> {
        return User.find(confirmEmailRequestDto.id, on: request).flatMap(to: User.self) { userFromDb in

            guard let user = userFromDb else {
                throw Abort(.badRequest, reason: "Invalid id or confirmation token.")
            }

            guard user.emailConfirmationGuid == confirmEmailRequestDto.confirmationGuid else {
                throw Abort(.badRequest, reason: "Invalid id or confirmation token.")
            }

            user.emailWasConfirmed = true
            return user.save(on: request)
        }.transform(to: HTTPStatus.ok)
    }

    private func getUserIdFromBearerToken(request: Request) throws -> UUID? {
        var userIdFromToken: UUID?
        if let bearer = request.http.headers.bearerAuthorization {

            let secureKeyStorage = try request.make(SecureKeyStorage.self)
            let rsaKey: RSAKey = try .private(pem: secureKeyStorage.privateKey)
            let authorizationPayload = try JWT<AuthorizationPayload>(from: bearer.token, verifiedUsing: JWTSigner.rs512(key: rsaKey))

            if authorizationPayload.payload.exp < Date() {
                userIdFromToken = authorizationPayload.payload.id
            }
        }

        return userIdFromToken
    }

    private func createAuthorizationPayload(forUser user: User) -> AuthorizationPayload {
        let expirationDate = Date().addingTimeInterval(TimeInterval(3600.0))
        let authorizationPayload = AuthorizationPayload(
            id: user.id,
            name: user.name,
            email: user.email,
            exp: expirationDate
        )

        return authorizationPayload
    }

    private func createAccessToken(request: Request, forUser user: User) throws -> String {

        let authorizationPayload = self.createAuthorizationPayload(forUser: user)

        let secureKeyStorage = try request.make(SecureKeyStorage.self)
        let rsaKey: RSAKey = try .private(pem: secureKeyStorage.privateKey)
        let data = try JWT(payload: authorizationPayload).sign(using: JWTSigner.rs512(key: rsaKey))
        let accessToken = String(data: data, encoding: .utf8) ?? ""

        return accessToken
    }
}
