# SwiftData Migration Guide

## Overview
This app has been upgraded to use SwiftData for persistent storage instead of UserDefaults. The migration happens automatically on first launch after the update.

## What Happens During Migration

### For Users Upgrading
1. **Automatic Backup**: Your existing data is backed up to a JSON file in Documents folder
2. **Migration**: All drone encounters are migrated from UserDefaults to SwiftData
3. **Verification**: The app verifies that all data was migrated successfully
4. **One-Time Process**: Migration only runs once and is marked complete

### Migration Safety Features

#### 1. **Crash Recovery** 
- **Previous Issue**: Early versions crashed when appending to SwiftData relationships during migration
- **Fix Applied**: Arrays are now built completely BEFORE creating SwiftData objects
- **Result**: Migration is now crash-free and safe for all users
- **Note**: Users who experienced the crash will automatically retry with the fixed code

#### 2. **Retry Logic**
- If migration fails, it automatically retries up to 3 times
- Uses exponential backoff (0.5 second delay between attempts)
- Each attempt is logged for debugging

#### 3. **Partial Success Handling**
- If some encounters fail to migrate, others still succeed
- Detailed logging shows how many succeeded/failed
- App continues to function with available data

#### 4. **Corrupted Database Recovery**
- If SwiftData store is corrupted, it's automatically deleted and recreated
- Migration flag is reset so data gets re-migrated from UserDefaults backup
- Graceful recovery without data loss

#### 5. **Fallback to UserDefaults**
- If migration completely fails, app continues using UserDefaults
- All existing functionality works normally
- Migration will be retried on next launch

#### 6. **Data Verification**
- After migration, app verifies data count matches
- Logs detailed information about what was migrated
- Ensures no data was lost in the process

```

## For Developers

### Testing Migration

#### Reset Migration (for testing)
```swift
// Add to a debug menu or settings screen
DataMigrationManager.shared.rollback()
```

#### Force Migration Complete (troubleshooting)
```swift
DataMigrationManager.shared.forceComplete()
```

#### Clean Up Legacy Data (after confirming migration)
```swift
DataMigrationManager.shared.cleanupLegacyData()
```


### Architecture

```
┌─────────────────────────────────────┐
│      WarDragonApp.swift             │
│  (Entry point, migration trigger)   │
└──────────────┬──────────────────────┘
               │
               v
┌─────────────────────────────────────┐
│   DataMigrationManager.swift        │
│  - Checks if migration needed       │
│  - Creates backups                  │
│  - Performs migration with retry    │
│  - Handles errors gracefully        │
└──────────────┬──────────────────────┘
               │
               v
┌─────────────────────────────────────┐
│   DroneDataModels.swift             │
│  - SwiftData model definitions      │
│  - Safe conversion helpers          │
│  - StoredDroneEncounter.from()      │
└─────────────────────────────────────┘
```

## Troubleshooting

### "Migration failed after all attempts"
- **Cause**: Unable to access SwiftData store
- **Solution**: Check device storage space, restart app
- **Fallback**: App uses UserDefaults, no data lost

### "SwiftData empty - Loaded from UserDefaults"
- **Cause**: Migration hasn't run yet or failed previously
- **Solution**: Migration will run automatically on next launch
- **Note**: This is normal on first launch after update

### Backup Files
- Location: `Documents/wardragon_backup_[timestamp].json`
- Format: JSON with base64-encoded encounter data
- Purpose: Safety net if migration fails
- Cleanup: Can be deleted after successful migration verification

## User-Facing Benefits

1. **Better Performance**: SwiftData is optimized for iOS
2. **Proper Relationships**: Flight points and signatures properly linked
3. **Query Capabilities**: Can filter and search encounters efficiently
4. **iCloud Sync Ready**: SwiftData supports CloudKit integration
5. **Type Safety**: Compile-time checks prevent data corruption

## Migration Timeline

- **Version 1.0**: UserDefaults storage
- **Version 2.0**: SwiftData migration added
- **Future**: UserDefaults backup can be removed after 1-2 releases

## Notes for Release

### App Store Release Notes
```
This version includes a one-time data migration to improve performance and reliability
• Your data is automatically backed up before migration
• Migration happens automatically on first launch
• If it fails to launch, close the app and open again
```
---

**Last Updated**: January 5, 2026
**Migration Version**: 1
**Status**: Production Ready
