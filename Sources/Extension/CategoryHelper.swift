//
//  CategoryHelper.swift
//  KumulosSDK
//
//  Created by Andrew Lindsay on 16/01/2020.
//  Copyright © 2020 Kumulos. All rights reserved.
//

import Foundation
import UserNotifications

internal let MAX_DYNAMIC_CATEGORIES = 128
internal let DYNAMIC_CATEGORY_USER_DEFAULTS_KEY = "__kumulos__dynamic__categories__"
internal let DYNAMIC_CATEGORY_IDENTIFIER = "__kumulos_category_%d__"

internal class CategoryHelper {
    internal static func getCategoryIdForMessageId(messageId: Int) -> String {
        return String(format: DYNAMIC_CATEGORY_IDENTIFIER, messageId)
    }
    
    internal static func registerCategory(category: UNNotificationCategory) -> Void {
        var categorySet = getExistingCategories()
        var storedDynamicCategories = getExistingDynamicCategoriesList()
        
        categorySet.insert(category)
        storedDynamicCategories.append(category.identifier)
        
        pruneCategoriesAndSave(categories: categorySet, dynamicCategories: storedDynamicCategories)
        
        // Force a reload of the categories
        _ = getExistingCategories()
    }
    
    internal static func getExistingCategories()-> Set<UNNotificationCategory> {
        let blocker = DispatchSemaphore(value: 0)
        var returnedCategories=Set<UNNotificationCategory>()
        
        UNUserNotificationCenter.current().getNotificationCategories { (categories: Set<UNNotificationCategory>) in
            returnedCategories = categories.filter { (_) -> Bool in
                return true
            }
            
            blocker.signal();
        }
        
        _ = blocker.wait(timeout: DispatchTime.now() + DispatchTimeInterval.seconds(5));
        
        return returnedCategories
    }
    
    internal static func getExistingDynamicCategoriesList() -> [String] {
        let blocker = DispatchSemaphore(value: 1)
        blocker.wait()
        defer {
            blocker.signal()
        }
            
        if let existingArray = UserDefaults.standard.object(forKey: DYNAMIC_CATEGORY_USER_DEFAULTS_KEY) {
            return existingArray as! [String]
        }

        let newArray = [String]()
        
        UserDefaults.standard.set(newArray, forKey: DYNAMIC_CATEGORY_USER_DEFAULTS_KEY)
        UserDefaults.standard.synchronize()
        
        return newArray
    }
        
    internal static func pruneCategoriesAndSave(categories: Set<UNNotificationCategory>, dynamicCategories: [String]) -> Void {
        if (dynamicCategories.count <= MAX_DYNAMIC_CATEGORIES) {
            UNUserNotificationCenter.current().setNotificationCategories(categories)
            UserDefaults.standard.set(dynamicCategories, forKey: DYNAMIC_CATEGORY_USER_DEFAULTS_KEY)
            return
        }
        
        let categoriesToRemove = dynamicCategories.prefix(dynamicCategories.count - MAX_DYNAMIC_CATEGORIES)
        
        let prunedCategories = categories.filter { (category) -> Bool in
            return categoriesToRemove.firstIndex(of: category.identifier) == nil
        }
        
        let prunedDynamicCategories = dynamicCategories.filter { (cat) -> Bool in
            return categoriesToRemove.firstIndex(of: cat) == nil
        }
        
        UNUserNotificationCenter.current().setNotificationCategories(prunedCategories)
        UserDefaults.standard.set(prunedDynamicCategories, forKey: DYNAMIC_CATEGORY_USER_DEFAULTS_KEY)
    }
}
