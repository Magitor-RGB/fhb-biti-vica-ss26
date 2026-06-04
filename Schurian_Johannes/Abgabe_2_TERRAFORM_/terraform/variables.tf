# ============================================================
# variables.tf – Eingabevariablen für die Terraform Konfiguration
# ============================================================

variable "zone" {
  description = "Exoscale Zone, in der die VM erstellt wird"
  type        = string
  # Wien (Österreich) als Standard – am nächsten für österreichische Nutzer
  default     = "at-vie-1"
}
