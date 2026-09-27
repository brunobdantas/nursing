import 'package:nursing_clinical_core/core/sync/sync_service.dart';

final class FakeClinicalSyncCoordinator implements ClinicalSyncCoordinator {
  FakeClinicalSyncCoordinator({
    ClinicalSyncStatus? localStatus,
    ClinicalSyncStatus? syncStatus,
  }) : localStatusValue =
           localStatus ??
           const ClinicalSyncStatus(
             state: ClinicalSyncState.offlineAvailable,
             hasLocalContent: true,
             contentVersion: 'clinical-release-v1-test',
           ),
       syncStatusValue =
           syncStatus ??
           const ClinicalSyncStatus(
             state: ClinicalSyncState.current,
             hasLocalContent: true,
             contentVersion: 'clinical-release-v1-test',
           );

  ClinicalSyncStatus localStatusValue;
  ClinicalSyncStatus syncStatusValue;
  int localStatusCalls = 0;
  int syncCalls = 0;

  @override
  Future<ClinicalSyncStatus> localStatus() async {
    localStatusCalls += 1;
    return localStatusValue;
  }

  @override
  Future<ClinicalSyncStatus> syncIfNeeded() async {
    syncCalls += 1;
    return syncStatusValue;
  }
}
