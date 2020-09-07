//
//  KumulosCheckins.swift
//  KumulosSDK
//
//  Copyright © 2020 Kumulos. All rights reserved.
//

import Foundation

public enum CheckinValidationError : Error {
    case atLeastOneContactRequired
    case partySizeSmallerThanNumberOfContacts
    case unexpectedEmptyValue(_ field:String)
}

public enum CheckinOperationError : Error {
    case networkError(_ err:Error?)
    case jsonError(_ err: Error)
    case invalidResponse(_ res: HTTPURLResponse)
    case checkinIdRequired
}

public enum CheckinOutcome<T> {
    case failure(_ err: CheckinOperationError)
    case success(_ result: T)
}

fileprivate func assertNotEmptyIfGiven(_ field: String, value:String?) throws {
    if value != nil && value!.count < 1 {
        throw CheckinValidationError.unexpectedEmptyValue(field)
    }
}

public struct KumulosCheckin : Codable {
    public struct Contact : Codable {
        public let id: UInt?
        public let checkinId: UInt?

        public let lastName: String
        public let firstName: String?
        public let emailAddress: String?
        public let smsNumber: String?
        public let meta: [String:String]?

        public let checkedOutAt: Date?

        public init(withLastName lastName: String, firstName: String? = nil, smsNumber: String? = nil, emailAddress: String? = nil, meta: [String:String]? = nil) throws {
            try assertNotEmptyIfGiven("lastName", value: lastName)
            try assertNotEmptyIfGiven("firstName", value: firstName)
            try assertNotEmptyIfGiven("smsNumber", value: smsNumber)
            try assertNotEmptyIfGiven("emailAddress", value: emailAddress)

            self.lastName = lastName
            self.firstName = firstName
            self.emailAddress = emailAddress
            self.smsNumber = smsNumber
            self.meta = meta

            id = nil
            checkinId = nil
            checkedOutAt = nil
        }
    }

    private var totalPartySize: Int

    public let id:UInt?
    public let location:String
    public let contacts: [Contact]
    public var partySize: Int {
        self.totalPartySize == 0 ? self.contacts.count : self.totalPartySize
    }

    public let checkedInAt: Date?
    public let checkedOutAt: Date?

    public init(atLocation location: String, withContacts contacts:[Contact], andPartySize partySize: Int) throws {
        guard contacts.count > 0 else {
            throw CheckinValidationError.atLeastOneContactRequired
        }
        if partySize > 0 && partySize < contacts.count {
            throw CheckinValidationError.partySizeSmallerThanNumberOfContacts
        }

        id = nil
        checkedInAt = nil
        checkedOutAt = nil

        self.location = location
        self.contacts = contacts
        totalPartySize = partySize
    }

    public init(atLocation location: String, withContacts contacts:[Contact]) throws {
        try self.init(atLocation: location, withContacts: contacts, andPartySize: 0)
    }

    enum DecodingKeys: String, CodingKey {
        case id
        case location
        case contacts
        case partySize
        case checkedInAt
        case checkedOutAt
    }

    enum EncodingKeys: String, CodingKey {
        case location
        case contacts
        case partySize
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: DecodingKeys.self)
        id = try values.decode(UInt.self, forKey: .id)
        location = try values.decode(String.self, forKey: .location)
        totalPartySize = try values.decode(Int.self, forKey: .partySize)
        contacts = try values.decode([Contact].self, forKey: .contacts)
        checkedInAt = try values.decodeIfPresent(Date.self, forKey: .checkedInAt)
        checkedOutAt = try values.decodeIfPresent(Date.self, forKey: .checkedOutAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: EncodingKeys.self)
        try container.encode(location, forKey: .location)
        try container.encode(contacts, forKey: .contacts)
        try container.encode(partySize, forKey: .partySize)
    }
}

fileprivate struct CheckinRequestData : Encodable {
    let deviceKey: String
    let checkin: KumulosCheckin

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: EncodingKeys.self)
        try container.encode(checkin.location, forKey: .location)
        try container.encode(checkin.contacts, forKey: .contacts)
        try container.encode(checkin.partySize, forKey: .partySize)
        try container.encode(deviceKey, forKey: .deviceKey)
        try container.encode(TimeZone.autoupdatingCurrent.identifier, forKey: .tz)
    }

    enum EncodingKeys: String, CodingKey {
        case location
        case contacts
        case partySize
        case deviceKey
        case tz
    }
}

public class KumulosCheckinClient {
    private static let crmUrl = "https://crm.kumulos.com"
    private static let deviceKeyLock = DispatchSemaphore(value: 1)
    private static let kDeviceKeyPref = "kumulosCheckinsDeviceKey"

    private let httpClient: KSHttpClient
    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder

    public init() {
        httpClient = KSHttpClient(
            baseUrl: URL(string: KumulosCheckinClient.crmUrl)!,
            requestFormat: .rawData,
            responseFormat: .rawData,
            additionalHeaders: [
                "Content-Type": "application/json",
                "Accept": "appliction/json"
            ]
        )
        httpClient.setBasicAuth(user: Kumulos.getInstance().config.apiKey, password: Kumulos.getInstance().config.secretKey)
        jsonEncoder = JSONEncoder()

        // https://stackoverflow.com/a/46458771
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"

        jsonDecoder = JSONDecoder()
        jsonDecoder.dateDecodingStrategy = .formatted(formatter)
    }

    public func checkIn(_ checkin: KumulosCheckin, onComplete: @escaping (CheckinOutcome<KumulosCheckin>) -> Void) {
        let encodedUserId = KSHttpUtil.urlEncode(Kumulos.currentUserIdentifier) ?? ""
        let path = "/v1/users/\(encodedUserId)/checkins"

        do {
            let reqData = try jsonEncoder.encode(CheckinRequestData(deviceKey: deviceKey(), checkin: checkin))

            httpClient.sendRequest(.POST, toPath: path, data: reqData, onSuccess: makeSuccessHandler(201, KumulosCheckin.self, onComplete)) { (res, err) in
                onComplete(.failure(.networkError(err)))
            }
        } catch {
            onComplete(.failure(.jsonError(error)))
        }
    }

    public func getOpenCheckins(onComplete: @escaping (CheckinOutcome<[KumulosCheckin]>) -> Void) {
        let encodedUserId = KSHttpUtil.urlEncode(Kumulos.currentUserIdentifier) ?? ""
        let encodedKey = KSHttpUtil.urlEncode(deviceKey()) ?? ""
        let path = "/v1/users/\(encodedUserId)/open-checkins?deviceKey=\(encodedKey)"

        httpClient.sendRequest(.GET, toPath: path, data: nil, onSuccess: makeSuccessHandler(200, [KumulosCheckin].self, onComplete)) { (res, err) in
            onComplete(.failure(.networkError(err)))
        }
    }

    public func checkOut(_ checkin: KumulosCheckin, onComplete: @escaping (CheckinOutcome<KumulosCheckin>) -> Void) {
        checkOut(checkin: checkin, onComplete: onComplete)
    }

    public func checkOutContact(_ contact: KumulosCheckin.Contact, onComplete: @escaping (CheckinOutcome<KumulosCheckin>) -> Void) {
        checkOut(contact: contact, onComplete: onComplete)
    }

    private func checkOut(checkin: KumulosCheckin? = nil, contact: KumulosCheckin.Contact? = nil, onComplete: @escaping (CheckinOutcome<KumulosCheckin>) -> Void) {
        let encodedUserId = KSHttpUtil.urlEncode(Kumulos.currentUserIdentifier) ?? ""
        let encodedKey = KSHttpUtil.urlEncode(deviceKey()) ?? ""
        var path: String

        if let checkin = checkin, let id = checkin.id {
            path = "/v1/users/\(encodedUserId)/checkins/\(id)?deviceKey=\(encodedKey)"
        }
        else if let contact = contact, let checkinId = contact.checkinId, let id = contact.id {
            path = "/v1/users/\(encodedUserId)/checkins/\(checkinId)/contacts/\(id)?deviceKey=\(encodedKey)"
        }
        else {
            onComplete(.failure(.checkinIdRequired))
            return
        }

        httpClient.sendRequest(.DELETE, toPath: path, data: nil, onSuccess: makeSuccessHandler(200, KumulosCheckin.self, onComplete)) { (res, err) in
            onComplete(.failure(.networkError(err)))
        }
    }

    private func makeSuccessHandler<T: Decodable>(_ expectedStatusCode: Int, _ responseType: T.Type, _ onComplete: @escaping (CheckinOutcome<T>) -> Void) -> (HTTPURLResponse?, Any?) -> Void {
        return { (res, data) in
            guard let response = res else {
                onComplete(.failure(.networkError(nil)))
                return
            }
            guard response.statusCode == expectedStatusCode else {
                onComplete(.failure(.invalidResponse(response)))
                return
            }
            guard let jsonData = data as? Data else {
                onComplete(.failure(.invalidResponse(response)))
                return
            }

            do {
                let checkin = try self.jsonDecoder.decode(responseType, from: jsonData)
                onComplete(.success(checkin))
            } catch {
                onComplete(.failure(.jsonError(error)))
            }
        }
    }

    private func deviceKey() -> String {
        KumulosCheckinClient.deviceKeyLock.wait()
        defer { KumulosCheckinClient.deviceKeyLock.signal() }

        if let key = KeyValPersistenceHelper.object(forKey: KumulosCheckinClient.kDeviceKeyPref) as? String {
            return key
        }

        var bytes = [Int8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)

        if status != errSecSuccess {
            return ""
        }

        let data = Data(bytes: bytes, count: bytes.count)
        let base64Key = data.base64EncodedString()

        KeyValPersistenceHelper.set(base64Key, forKey: KumulosCheckinClient.kDeviceKeyPref)

        return base64Key
    }
}
