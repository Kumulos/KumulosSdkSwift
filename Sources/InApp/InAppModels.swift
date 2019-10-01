
import Foundation
import CoreData

public enum InAppPresented : String {
    case IMMEDIATELY = "immediately"
    case NEXT_OPEN = "next-open"
    case NEVER = "never"
}

class InAppMessageEntity : NSManagedObject {
    @NSManaged var id : Int64
    @NSManaged var updatedAt: NSDate
    @NSManaged var presentedWhen: String
    @NSManaged var content: NSDictionary
    @NSManaged var data : NSDictionary?
    @NSManaged var badgeConfig : NSDictionary?
    @NSManaged var inboxConfig : NSDictionary?
    @NSManaged var dismissedAt : NSDate?
    @NSManaged var inboxFrom : NSDate?
    @NSManaged var inboxTo : NSDate?
}

public class InAppMessage: NSObject {
    internal(set) open var id: Int64
    internal(set) open var updatedAt: NSDate
    internal(set) open var content: NSDictionary
    internal(set) open var data : NSDictionary?
    internal(set) open var badgeConfig : NSDictionary?
    internal(set) open var inboxConfig : NSDictionary?
    internal(set) open var dismissedAt : NSDate?
    
    init(entity: InAppMessageEntity) {
        id = entity.id
        updatedAt = entity.updatedAt
        content = entity.content
        data = entity.data
        badgeConfig = entity.badgeConfig
        inboxConfig = entity.inboxConfig
        dismissedAt = entity.dismissedAt
    }

    public override func isEqual(_ object: Any?) -> Bool {
        if let other = object as? InAppMessage {
            return self.id == other.id
        }

        return super.isEqual(object)
    }
}
