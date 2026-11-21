/*
 * Copyright 2018 Google
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#ifndef FIRESTORE_CORE_INCLUDE_FIREBASE_FIRESTORE_FIRESTORE_ERRORS_H_
#define FIRESTORE_CORE_INCLUDE_FIREBASE_FIRESTORE_FIRESTORE_ERRORS_H_

namespace firebase {
namespace firestore {

/**
 * Error codes used by Cloud Firestore.
 *
 * The codes are in sync across Firestore SDKs on various platforms.
 */
enum Error {
  /** The operation completed successfully. */
  kErrorOk = 0,
  kErrorNone = 0,
  /** The operation was cancelled (typically by the caller). */
  kErrorCancelled = 1,
  /** Unknown error or an error from a different error domain. */
  kErrorUnknown = 2,
  kErrorInvalidArgument = 3,
  kErrorDeadlineExceeded = 4,
  /** Some requested document was not found. */
  kErrorNotFound = 5,
  /** Some document that we attempted to create already exists. */
  kErrorAlreadyExists = 6,
  /** The caller does not have permission to execute the specified operation. */
  kErrorPermissionDenied = 7,
  kErrorResourceExhausted = 8,
  kErrorFailedPrecondition = 9,
  kErrorAborted = 10,
  /** Operation was attempted past the valid range. */
  kErrorOutOfRange = 11,
  /** Operation is not implemented or not supported/enabled. */
  kErrorUnimplemented = 12,
  kErrorInternal = 13,
  kErrorUnavailable = 14,
  /** Unrecoverable data loss or corruption. */
  kErrorDataLoss = 15,
  kErrorUnauthenticated = 16
};

}  // namespace firestore
}  // namespace firebase

#endif  // FIRESTORE_CORE_INCLUDE_FIREBASE_FIRESTORE_FIRESTORE_ERRORS_H_
