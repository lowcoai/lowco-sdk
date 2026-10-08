package integrations

// Error is returned for any non-2xx response or transport failure.
type Error struct {
	Status  int
	Message string
	Payload any
}

func (e *Error) Error() string {
	return e.Message
}
