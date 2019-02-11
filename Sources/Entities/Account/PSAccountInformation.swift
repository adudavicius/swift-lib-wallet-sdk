import ObjectMapper

public class PSAccountInformation: Mappable {
    public let accountNumber: String
    public let ownerDisplayName: String
    public let ownerTitle: String
    public let ownerType: String
    public let type: String
    public let userId: Int
    public let status: String
    public let accountDescription: String
    public let ibans: [String]
    
    required public init?(map: Map) {
        do {
            accountNumber = try map.value("number")
            ownerDisplayName = try map.value("owner_display_name")
            ownerTitle = try map.value("owner_title")
            ownerType = try map.value("owner_type")
            type = try map.value("type")
            userId = try map.value("user_id")
            status = try map.value("status")
            accountDescription = try map.value("description")
            ibans = try map.value("ibans")
            
        } catch {
            print("\n")
            print(error)
            print("\n")
            return nil
        }
    }
    
    public func mapping(map: Map) {
    }
}
