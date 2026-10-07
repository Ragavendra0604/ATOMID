import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'hardware_device.dart';

final printJobManagerProvider = Provider((ref) => PrintJobManager());

class PrintJobManager {
  final Map<String, PrintJob> _jobs = {};

  /// Tracks a print job. Returns false if the exact job is already pending or printing,
  /// protecting against accidental duplicate receipt generation.
  bool startJob(
    String jobId,
    String transactionId,
    String docType,
    String printerId,
  ) {
    if (_jobs.containsKey(jobId) && _jobs[jobId]!.status != 'FAILED') {
      return false; // Prevent duplicate active print attempts for the same job
    }

    int previousAttempts = _jobs.containsKey(jobId)
        ? _jobs[jobId]!.attempts
        : 0;

    _jobs[jobId] = PrintJob(
      jobId: jobId,
      transactionId: transactionId,
      documentType: docType,
      printerId: printerId,
      status: 'PRINTING',
      attempts: previousAttempts,
    );

    // Prevent unbounded memory growth by keeping only the 50 most recent jobs
    if (_jobs.length > 50) {
      final oldestJobId = _jobs.keys.first;
      _jobs.remove(oldestJobId);
    }

    return true;
  }

  void completeJob(String jobId) {
    if (_jobs.containsKey(jobId)) {
      _jobs[jobId]!.status = 'COMPLETED';
    }
  }

  void failJob(String jobId, String error) {
    if (_jobs.containsKey(jobId)) {
      _jobs[jobId]!.status = 'FAILED';
      _jobs[jobId]!.error = error;
      _jobs[jobId]!.attempts += 1;
    }
  }

  PrintJob? getJob(String jobId) => _jobs[jobId];
}
