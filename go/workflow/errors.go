package workflow

// Error is returned for any non-2xx response or transport failure, and by the
// deprecated webhook methods, which send no request (Status 0).
type Error struct {
	Status  int
	Message string
	Payload any
}

func (e *Error) Error() string {
	return e.Message
}
