package lowcodb

import "time"

const (
	HeaderOrgID = "X-Org-Id"
)

type BaseEntity struct {
	ID        string     `json:"id,omitempty"`
	OrgID     string     `json:"orgId,omitempty"`
	PRN       string     `json:"prn,omitempty"`
	CreatedAt time.Time  `json:"createdAt,omitempty"`
	UpdatedAt *time.Time `json:"updatedAt,omitempty"`
	CreatedBy string     `json:"createdBy,omitempty"`
	UpdatedBy string     `json:"updatedBy,omitempty"`
}

type BaseType string

const (
	BaseTypeInternal BaseType = "internal"
	BaseTypeExternal BaseType = "external"
)

type Base struct {
	BaseEntity
	Name         string   `json:"name,omitempty"`
	Description  string   `json:"description,omitempty"`
	ConnectionID string   `json:"connectionId,omitempty"`
	BaseType     BaseType `json:"baseType,omitempty"`
	Schema       string   `json:"schema,omitempty"`
}

type Table struct {
	BaseEntity
	BaseID      string         `json:"baseId,omitempty"`
	Name        string         `json:"name,omitempty"`
	Description string         `json:"description,omitempty"`
	TableKey    string         `json:"tableKey,omitempty"`
	Metadata    map[string]any `json:"metadata,omitempty"`
}

type ColumnTrimmed struct {
	Name     string `json:"name,omitempty"`
	DataType string `json:"dataType,omitempty"`
}

type TableWithColumns struct {
	Table
	Columns []ColumnTrimmed `json:"columns,omitempty"`
}

type ColumnMetadata struct {
	Option          []string `json:"option,omitempty"`
	IsNotNull       bool     `json:"isNotNull,omitempty"`
	IsPrimaryKey    bool     `json:"isPrimaryKey,omitempty"`
	IsUnique        bool     `json:"isUnique,omitempty"`
	IsAutoIncrement bool     `json:"isAutoIncrement,omitempty"`
	MaxLength       int      `json:"maxLength,omitempty"`
	SelectType      string   `json:"selectType,omitempty"`
}

type ValidationError struct {
	Rule  string `json:"rule,omitempty"`
	Error string `json:"error,omitempty"`
}

type DropdownOption struct {
	Label string `json:"label,omitempty"`
	Value string `json:"value,omitempty"`
}

type Field struct {
	Value       any               `json:"value,omitempty"`
	DataType    string            `json:"dataType,omitempty"`
	Options     []DropdownOption  `json:"options,omitempty"`
	Validations []ValidationError `json:"validations,omitempty"`
}

type ValidationResponse struct {
	Value  any               `json:"value,omitempty"`
	Errors []ValidationError `json:"errors,omitempty"`
}

type Column struct {
	BaseEntity
	BaseID       string            `json:"baseId,omitempty"`
	TableID      string            `json:"tableId,omitempty"`
	Name         string            `json:"name,omitempty"`
	DataType     string            `json:"dataType,omitempty"`
	Metadata     ColumnMetadata    `json:"metadata,omitempty"`
	DefaultValue string            `json:"defaultValue,omitempty"`
	Validations  []ValidationError `json:"validations,omitempty"`
}

type TableIndex struct {
	BaseEntity
	BaseID    string   `json:"baseId,omitempty"`
	TableID   string   `json:"tableId,omitempty"`
	IndexName string   `json:"indexName,omitempty"`
	Columns   []string `json:"columns,omitempty"`
	IsUnique  bool     `json:"isUnique,omitempty"`
}

// TableIndexUpdateInput is the rename-only payload accepted by PUT /tables/{tableId}/index/{id}.
type TableIndexUpdateInput struct {
	IndexName string `json:"indexName,omitempty"`
}

type TableTrigger struct {
	BaseEntity
	BaseID       string `json:"baseId,omitempty"`
	TableID      string `json:"tableId,omitempty"`
	EventType    string `json:"eventType,omitempty"`
	EventTime    string `json:"eventTime,omitempty"`
	WorkflowID   string `json:"workflowId,omitempty"`
	WorkflowName string `json:"workflowName,omitempty"` // populated by ListTriggers
}

type TableWebhook struct {
	BaseEntity
	BaseID     string            `json:"baseId,omitempty"`
	TableID    string            `json:"tableId,omitempty"`
	URL        string            `json:"url,omitempty"`
	Headers    map[string]string `json:"headers,omitempty"`
	EventTypes []string          `json:"eventTypes,omitempty"`
	Method     string            `json:"method,omitempty"`
	Active     bool              `json:"active,omitempty"`
}

type TableViewKind string

const (
	TableViewKindView         TableViewKind = "view"
	TableViewKindMaterialized TableViewKind = "materialized_view"
)

type TableView struct {
	BaseEntity
	BaseID      string         `json:"baseId,omitempty"`
	Name        string         `json:"name,omitempty"`
	Description string         `json:"description,omitempty"`
	ViewKey     string         `json:"viewKey,omitempty"`
	Kind        TableViewKind  `json:"kind,omitempty"`
	Definition  string         `json:"definition,omitempty"`
	Metadata    map[string]any `json:"metadata,omitempty"`
}

// Record is an arbitrary row in a user-defined table. The manager always
// returns the system fields (id, createdAt, …) alongside user columns.
type Record map[string]any

type RunQueryRequest struct {
	Query  string `json:"query"`
	BaseID string `json:"baseId,omitempty"`
}

type RowsResponse struct {
	Rows []map[string]any `json:"rows,omitempty"`
}

type SuggestionsResponse struct {
	Suggestions []string `json:"suggestions,omitempty"`
}

type CountResponse struct {
	Count int64 `json:"count,omitempty"`
}

type DeleteCountResponse struct {
	DeletedCount int64 `json:"deletedCount,omitempty"`
}

type ViewRefreshRequest struct {
	Concurrent bool `json:"concurrent"`
}

type ViewRefreshResponse struct {
	Status string `json:"status,omitempty"`
}

type ColumnsBulkResult struct {
	Created []Column         `json:"created,omitempty"`
	Failed  []map[string]any `json:"failed,omitempty"`
}

type RecordsBulkResult struct {
	Updated []Record         `json:"updated,omitempty"`
	Failed  []map[string]any `json:"failed,omitempty"`
}

type OverviewCounts struct {
	Totals map[string]int   `json:"totals,omitempty"`
	Bases  []map[string]any `json:"bases,omitempty"`
}

type SyncTablesResult struct {
	TablesAdded   []string `json:"tablesAdded,omitempty"`
	TablesRemoved []string `json:"tablesRemoved,omitempty"`
	TablesUpdated []string `json:"tablesUpdated,omitempty"`
	Errors        []string `json:"errors,omitempty"`
}

type DashboardResponse map[string]any

type APIError struct {
	Code    string         `json:"code,omitempty"`
	Message string         `json:"message,omitempty"`
	Details map[string]any `json:"details,omitempty"`
}

// ListParams is a convenience builder for the common
// pageNo / size / filter / sort query parameters.
type ListParams struct {
	PageNo int
	Size   int
	Filter string
	Sort   string
}
