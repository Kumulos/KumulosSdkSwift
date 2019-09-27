
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
    internal(set) open var presentedWhen: InAppPresented//??? this not set in Objective-C
    internal(set) open var content: NSDictionary
    internal(set) open var data : NSDictionary?
    internal(set) open var badgeConfig : NSDictionary?
    internal(set) open var inboxConfig : NSDictionary?
    internal(set) open var dismissedAt : NSDate?
    
    init(entity: InAppMessageEntity) {
        id = entity.id
        updatedAt = entity.updatedAt
        presentedWhen = InAppPresented.NEVER
        
        if (entity.presentedWhen == InAppPresented.IMMEDIATELY.rawValue) {
            presentedWhen = InAppPresented.IMMEDIATELY
        }
        
        if (entity.presentedWhen == InAppPresented.NEXT_OPEN.rawValue){
            presentedWhen = InAppPresented.NEXT_OPEN
        }
        
        content = entity.content
        data = entity.data
        badgeConfig = entity.badgeConfig
        inboxConfig = entity.inboxConfig
        dismissedAt = entity.dismissedAt
    }
    
    //    - (BOOL)isEqual:(id)other
    //    {
    //    if (other && [other isKindOfClass:KSInAppMessage.class]) {
    //    return [self.id isEqualToNumber:((KSInAppMessage*)other).id];
    //    }
    //
    //    return [super isEqual:other];
    //    }
    //
    //    - (NSUInteger)hash
    //    {
    //    return [self.id hash];
    //    }
}
