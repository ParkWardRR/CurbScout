package vast

import (
	_ "embed"
)

//go:embed provision_embed.sh
var ProvisionScript string
