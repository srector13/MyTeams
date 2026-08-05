//
//  CoreDataManipulation.swift
//  myTeams
//
//  Created by Stephen Rector on 3/3/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//


//NOT USED WILL DELETE//

import UIKit
import CoreData
import Foundation
 
class CoreDataManager {
    
    static let shared = CoreDataManager(moc: NSManagedObjectContext.current)
    
    var moc: NSManagedObjectContext
    
    private init(moc: NSManagedObjectContext) {
        self.moc = moc
    }
    
    func getSavedImages() -> [SavedImage] {
        var savedImages = [SavedImage]()
        let savedImageRequest: NSFetchRequest<SavedImage> = SavedImage.fetchRequest()
        
        do {
            savedImages = try self.moc.fetch(savedImageRequest)
        } catch let error as NSError {
            print(error)
        }
        
        return savedImages
    }
    
    func saveImage(imageName: String) {
        
        let entity = NSEntityDescription.entity(forEntityName: "SavedImage", in: moc)
        let newImage = NSManagedObject(entity: entity!, insertInto: moc)
        newImage.setValue("Shashikant", forKey: "img")
        newImage.setValue("image", forKey: "imgName")
        
        do {
           try moc.save()
          } catch {
           print("Failed saving")
        }
    }
}

extension NSManagedObjectContext {
    static var current: NSManagedObjectContext {
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        return appDelegate.persistentContainer.viewContext
    }
}


