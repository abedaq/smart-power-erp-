package services

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"
	"unicode"
)

func boolPtr(b bool) *bool {
	return &b
}

func getStringValue(s *string, def string) string {
	if s != nil && *s != "" {
		return *s
	}
	return def
}

// ToEnglishDigits converts Eastern Arabic (٠-٩) and Persian (۰-۹) numerals to standard Western English digits (0-9).
func ToEnglishDigits(s string) string {
	var builder strings.Builder
	for _, r := range s {
		if r >= 0x0660 && r <= 0x0669 {
			builder.WriteRune(r - 0x0660 + '0')
		} else if r >= 0x06F0 && r <= 0x06F9 {
			builder.WriteRune(r - 0x06F0 + '0')
		} else {
			builder.WriteRune(r)
		}
	}
	return builder.String()
}

// NormalizeCustomerPhone strips any prefixes (+, 967, 0, spaces, dashes) and returns pure English digits.
func NormalizeCustomerPhone(phone string) string {
	eng := ToEnglishDigits(phone)
	var digits strings.Builder
	for _, r := range eng {
		if unicode.IsDigit(r) {
			digits.WriteRune(r)
		}
	}
	s := digits.String()
	for strings.HasPrefix(s, "00967") {
		s = s[5:]
	}
	for strings.HasPrefix(s, "967") {
		s = s[3:]
	}
	for strings.HasPrefix(s, "0") {
		s = s[1:]
	}
	return s
}

// NormalizeWhatsAppPhone formats a phone number for WhatsApp delivery with appropriate country code (defaults to 967 for Yemeni numbers).
func NormalizeWhatsAppPhone(phone string) string {
	clean := NormalizeCustomerPhone(phone)
	if clean == "" {
		return ""
	}
	if strings.HasPrefix(clean, "967") {
		return clean
	}
	// If already a full international number (e.g. Saudi 966..., UAE 971..., etc. >= 11 digits)
	if len(clean) >= 11 {
		return clean
	}
	return "967" + clean
}

// ValidateWhatsAppPhone validates and formats a phone number for WhatsApp transmission.
func ValidateWhatsAppPhone(phone string) (string, error) {
	trimmed := strings.TrimSpace(phone)
	if trimmed == "" {
		return "", fmt.Errorf("رقم الهاتف غير متوفر")
	}
	normalized := NormalizeWhatsAppPhone(trimmed)
	if len(normalized) < 8 || len(normalized) > 16 {
		return "", fmt.Errorf("رقم الهاتف غير صالح للإرسال: %s", phone)
	}
	return normalized, nil
}

var (
	yearRegex = regexp.MustCompile(`\b(20\d{2})\b`)
	isoCycleRegex = regexp.MustCompile(`^(\d{4})-(\d{1,2})(?:-([12]|15|30|A|B))?$`)
)

// GetCycleSortIndex parses any cycle string (Arabic or ISO) into an integer sort key: (Year * 24) + ((Month - 1) * 2) + cycleNum
func GetCycleSortIndex(cycleStr string) int {
	trimmed := strings.TrimSpace(cycleStr)
	if trimmed == "" {
		return 0
	}

	// 1. Direct match for ISO format e.g. "2026-08-1", "2026-08-2", "2026-09-1"
	if matches := isoCycleRegex.FindStringSubmatch(trimmed); len(matches) > 0 {
		year, _ := strconv.Atoi(matches[1])
		month, _ := strconv.Atoi(matches[2])
		cycleNum := 1
		if len(matches) > 3 && (matches[3] == "2" || matches[3] == "30" || strings.ToUpper(matches[3]) == "B") {
			cycleNum = 2
		}
		if year >= 2000 && month >= 1 && month <= 12 {
			return (year * 24) + ((month - 1) * 2) + cycleNum
		}
	}

	norm := strings.ReplaceAll(trimmed, "أ", "ا")
	norm = strings.ReplaceAll(norm, "إ", "ا")
	norm = strings.ReplaceAll(norm, "آ", "ا")
	norm = strings.TrimPrefix(norm, "شهر ")
	norm = strings.TrimSpace(norm)

	year := 2026
	if match := yearRegex.FindString(norm); match != "" {
		if y, err := strconv.Atoi(match); err == nil && y >= 2000 && y <= 2100 {
			year = y
		}
	}

	// Remove year before checking cycle 2 to avoid false positive on years starting with 20
	normWithoutYear := yearRegex.ReplaceAllString(norm, "")

	months := []struct {
		name  string
		month int
	}{
		{"يناير", 1}, {"فبراير", 2}, {"مارس", 3}, {"ابريل", 4},
		{"مايو", 5}, {"يونيو", 6}, {"يوليو", 7}, {"اغسطس", 8},
		{"سبتمبر", 9}, {"اكتوبر", 10}, {"نوفمبر", 11}, {"ديسمبر", 12},
	}

	for _, m := range months {
		if strings.Contains(normWithoutYear, m.name) {
			cycleNum := 1
			cleanedForCycle := strings.ReplaceAll(normWithoutYear, m.name, "")

			if strings.Contains(cleanedForCycle, "2") || strings.Contains(cleanedForCycle, "30") || strings.Contains(cleanedForCycle, "B") {
				cycleNum = 2
			}
			return (year * 24) + ((m.month - 1) * 2) + cycleNum
		}
	}

	return 0
}

// FormatCanonicalCycle converts any cycle format (ISO or Arabic) into standardized Arabic representation (e.g. "أغسطس 1", "أغسطس 2", "يناير 1 - 2027")
func FormatCanonicalCycle(cycleStr string) string {
	idx := GetCycleSortIndex(cycleStr)
	if idx <= 0 {
		return strings.TrimSpace(cycleStr)
	}

	year := idx / 24
	rem := idx % 24
	if rem == 0 {
		year--
		rem = 24
	}

	cycleNum := 1
	if rem%2 == 0 {
		cycleNum = 2
	}
	monthIdx := ((rem - cycleNum) / 2) + 1

	arabicMonths := []string{
		"", "يناير", "فبراير", "مارس", "أبريل", "مايو", "يونيو",
		"يوليو", "أغسطس", "سبتمبر", "أكتوبر", "نوفمبر", "ديسمبر",
	}

	mName := "أغسطس"
	if monthIdx >= 1 && monthIdx <= 12 {
		mName = arabicMonths[monthIdx]
	}

	if year == 2026 {
		return fmt.Sprintf("%s %d", mName, cycleNum)
	}
	return fmt.Sprintf("%s %d - %d", mName, cycleNum, year)
}