import ObjectMapper

public class PSTransaction: Mappable {
    public var autoConfirm: Bool?
    public var useAllowance: Bool?
    public var payments: Array<PSPayment>?
    public var key: String?
    public var status: String?
    public var project: PSProject?
    
    required public init?(map: Map) {
    }
    
    // Mappable
    public func mapping(map: Map) {
        autoConfirm     <- map["auto_confirm"]
        useAllowance    <- map["use_allowance"]
        payments        <- map["payments"]
        key             <- map["transaction_key"]
        status          <- map["status"]
        project         <- map["project"]
    }
}
