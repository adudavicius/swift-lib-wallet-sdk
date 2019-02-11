import ObjectMapper

public class PSAccountInformationFlags: Mappable {
    var `public` = false
    var savings = false
    
    required public init?(map: Map) {
    }
    
    public func mapping(map: Map) {
        `public` <- map["public"]
        savings  <- map["savings"]
    }
}
