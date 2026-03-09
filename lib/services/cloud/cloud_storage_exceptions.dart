class CloudStorageException implements Exception {
  const CloudStorageException();
}

// C di CRUD
class CouldNotCreateNoteException extends CloudStorageException {}

// R di CRUD
class CouldNotGetAllNotesException extends CloudStorageException {}

// U di CRUD
class CouldNotUpdateNoteException extends CloudStorageException {}

// D di CRUD
class CouldNotDeleteNoteException extends CloudStorageException {}