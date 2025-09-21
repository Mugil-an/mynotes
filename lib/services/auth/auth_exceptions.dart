//login exceptions


class UserNotFoundException implements Exception{}
class IncorrectPassword implements Exception{}


// register exceptions

class EmailAlreadyExistException implements Exception{}
class WeakPasswordException implements Exception{}
class InvalidEmailAuthException implements Exception{}

// generic exceptions

class  GenericAuthException implements Exception{}
class UserNotLoggedInExcaption implements Exception{}