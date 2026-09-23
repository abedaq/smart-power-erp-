package services

import (
	"bytes"
	"fmt"
	"io"
	"strconv"
	"strings"

	"smartpower/internal/database"
	"smartpower/internal/models"

	"github.com/xuri/excelize/v2"
	"gorm.io/gorm"
)

type ExcelService struct {
	db             *gorm.DB
	readingService *ReadingService
	billingService *BillingService
}

func NewExcelService(readingService *ReadingService, billingService *BillingService) *ExcelService {
	return &ExcelService{
		db:             database.DB,
		readingService: readingService,
		billingService: billingService,
	}
}

type ImportResult struct {
	TotalRows      int      `json:"total_rows"`
	SuccessfulRows int      `json:"successful_rows"`
	FailedRows     int      `json:"failed_rows"`
	Errors         []string `json:"errors"`
}

func (s *ExcelService) ImportReadingsExcel(reader io.Reader, cycleName, collectorName string) (*ImportResult, error) {
	f, err := excelize.OpenReader(reader)
	if err != nil {
		return nil, fmt.Errorf("failed to parse excel file: %w", err)
	}
	defer f.Close()

	sheetList := f.GetSheetList()
	if len(sheetList) == 0 {
		return nil, fmt.Errorf("excel file contains no sheets")
	}

	rows, err := f.GetRows(sheetList[0])
	if err != nil {
		return nil, fmt.Errorf("failed to read sheet rows: %w", err)
	}

	if len(rows) <= 1 {
		return nil, fmt.Errorf("excel file has no data rows")
	}

	result := &ImportResult{
		TotalRows: len(rows) - 1,
		Errors:    make([]string, 0),
	}

	for i, row := range rows[1:] {
		rowNum := i + 2
		if len(row) < 3 {
			result.FailedRows++
			result.Errors = append(result.Errors, fmt.Sprintf("Row %d: Missing required columns", rowNum))
			continue
		}

		subNum := strings.TrimSpace(row[0])
		readingStr := strings.TrimSpace(row[2])
		readingVal, err := strconv.ParseFloat(readingStr, 64)
		if err != nil {
			result.FailedRows++
			result.Errors = append(result.Errors, fmt.Sprintf("Row %d: Invalid reading value '%s'", rowNum, readingStr))
			continue
		}

		var customer models.Customer
		if err := s.db.Where("subscriber_number = ? OR CAST(id AS TEXT) = ?", subNum, subNum).First(&customer).Error; err != nil {
			result.FailedRows++
			result.Errors = append(result.Errors, fmt.Sprintf("Row %d: Customer '%s' not found", rowNum, subNum))
			continue
		}

		colName := collectorName
		if colName == "" {
			colName = "استيراد إكسل"
		}

		canonicalCycle := FormatCanonicalCycle(cycleName)
		if canonicalCycle == "" {
			canonicalCycle = "أغسطس 2"
		}

		_, err = s.readingService.CreateReading(CreateReadingRequest{
			CustomerID:      customer.ID,
			ReadingValue:    readingVal,
			CollectorName:   colName,
			ApprovalStatus:  "APPROVED",
			BillingCycle:    canonicalCycle,
		})

		if err != nil {
			result.FailedRows++
			result.Errors = append(result.Errors, fmt.Sprintf("Row %d (%s): %v", rowNum, customer.FullName, err))
		} else {
			result.SuccessfulRows++
		}
	}

	return result, nil
}

func (s *ExcelService) ExportCycleExcel(cycleName string) ([]byte, error) {
	var invoices []models.Invoice
	query := s.db.Joins("JOIN customers ON customers.id = invoices.customer_id AND customers.is_deleted = false").
		Preload("Customer").
		Preload("Customer.SubscriptionPlan").
		Preload("MeterReading").
		Order("customers.sort_order ASC, customers.id ASC, invoices.id ASC")

	cleanCycle := strings.TrimSpace(cycleName)
	if cleanCycle != "" && strings.ToUpper(cleanCycle) != "ALL" && cleanCycle != "كافة الدورات" {
		if s.billingService != nil {
			_ = s.billingService.EnsureCycleInvoices(cleanCycle)
		}
		aliases := getCycleAliases(cleanCycle)
		if len(aliases) > 0 {
			query = query.Where("invoices.billing_cycle IN ?", aliases)
		} else {
			query = query.Where("invoices.billing_cycle = ? OR invoices.billing_cycle ILIKE ?", cleanCycle, "%"+cleanCycle+"%")
		}
	}

	if err := query.Find(&invoices).Error; err != nil {
		return nil, err
	}

	f := excelize.NewFile()
	sheet := "تقرير_الفواتير"
	if cleanCycle != "" && strings.ToUpper(cleanCycle) != "ALL" && cleanCycle != "كافة الدورات" {
		sheet = fmt.Sprintf("فواتير_%s", strings.ReplaceAll(cleanCycle, "/", "_"))
	}
	f.SetSheetName("Sheet1", sheet)

	f.SetSheetView(sheet, 0, &excelize.ViewOptions{
		RightToLeft: boolPtr(true),
	})

	// Header Style
	headerStyle, _ := f.NewStyle(&excelize.Style{
		Font: &excelize.Font{
			Bold:  true,
			Color: "FFFFFF",
			Size:  11,
		},
		Fill: excelize.Fill{
			Type:    "pattern",
			Color:   []string{"1E3A8A"},
			Pattern: 1,
		},
		Alignment: &excelize.Alignment{
			Horizontal: "center",
			Vertical:   "center",
			WrapText:   true,
		},
		Border: []excelize.Border{
			{Type: "top", Color: "CBD5E1", Style: 1},
			{Type: "bottom", Color: "CBD5E1", Style: 1},
			{Type: "left", Color: "CBD5E1", Style: 1},
			{Type: "right", Color: "CBD5E1", Style: 1},
		},
	})

	// Data Row Style
	dataStyle, _ := f.NewStyle(&excelize.Style{
		Font: &excelize.Font{
			Size: 10,
		},
		Alignment: &excelize.Alignment{
			Horizontal: "center",
			Vertical:   "center",
		},
		Border: []excelize.Border{
			{Type: "top", Color: "E2E8F0", Style: 1},
			{Type: "bottom", Color: "E2E8F0", Style: 1},
			{Type: "left", Color: "E2E8F0", Style: 1},
			{Type: "right", Color: "E2E8F0", Style: 1},
		},
	})

	// Total / Summary Row Style
	totalStyle, _ := f.NewStyle(&excelize.Style{
		Font: &excelize.Font{
			Bold:  true,
			Color: "0F172A",
			Size:  11,
		},
		Fill: excelize.Fill{
			Type:    "pattern",
			Color:   []string{"E2E8F0"},
			Pattern: 1,
		},
		Alignment: &excelize.Alignment{
			Horizontal: "center",
			Vertical:   "center",
		},
		Border: []excelize.Border{
			{Type: "top", Color: "64748B", Style: 2},
			{Type: "bottom", Color: "64748B", Style: 2},
			{Type: "left", Color: "CBD5E1", Style: 1},
			{Type: "right", Color: "CBD5E1", Style: 1},
		},
	})

	blankIfZero := func(v float64) interface{} {
		if v == 0 {
			return ""
		}
		return v
	}

	headers := []string{
		"رقم الفاتورة",
		"رقم المشترك",
		"خط السير",
		"اسم المشترك",
		"العنوان",
		"رقم العداد",
		"رقم الهاتف",
		"القراءة السابقة",
		"القراءة الحالية",
		"الاستهلاك (ك.و)",
		"سعر الكيلو",
		"قيمة الاستهلاك",
		"رسوم الخدمة",
		"إجمالي الفاتورة",
		"المتأخرات",
		"إجمالي المستحق",
		"المسدد",
		"المتبقي",
		"الدورة الفوترية",
	}

	_ = f.SetRowHeight(sheet, 1, 28)

	for colIdx, h := range headers {
		cell, _ := excelize.CoordinatesToCellName(colIdx+1, 1)
		_ = f.SetCellValue(sheet, cell, h)
		_ = f.SetCellStyle(sheet, cell, cell, headerStyle)
	}

	var sumConsumption float64
	var sumConsumptionVal float64
	var sumFixedFee float64
	var sumTotalAmount float64
	var sumArrears float64
	var sumTotalDue float64
	var sumPaid float64
	var sumRemaining float64

	for rowIdx, inv := range invoices {
		r := rowIdx + 2
		_ = f.SetRowHeight(sheet, r, 22)

		custName := ""
		subNo := ""
		phone := ""
		route := ""
		address := ""
		meterNum := ""
		if inv.Customer != nil {
			custName = strings.TrimSpace(inv.Customer.FullName)
			subNo = strings.TrimSpace(inv.Customer.SubscriberNumber)
			phone = strings.TrimSpace(inv.Customer.PhoneNumber)
			if inv.Customer.RouteNumber != nil {
				route = strings.TrimSpace(*inv.Customer.RouteNumber)
			}
			if inv.Customer.Address != nil {
				address = strings.TrimSpace(*inv.Customer.Address)
			}
			if inv.Customer.MeterNumber != nil {
				meterNum = strings.TrimSpace(*inv.Customer.MeterNumber)
			}
		}

		invNum := fmt.Sprintf("INV-%06d", inv.ID)
		if inv.InvoiceNumber != nil && *inv.InvoiceNumber != "" {
			invNum = *inv.InvoiceNumber
		}

		sumConsumption += inv.Consumption
		sumConsumptionVal += inv.ConsumptionValue
		sumFixedFee += inv.FixedFeeSnapshot
		sumTotalAmount += inv.TotalAmount
		sumArrears += inv.Arrears
		sumTotalDue += inv.TotalDue
		sumPaid += inv.PaidAmount
		sumRemaining += inv.RemainingAmount

		cycleVal := ""
		if inv.BillingCycle != nil {
			cycleVal = strings.TrimSpace(*inv.BillingCycle)
		}
		if cycleVal == "" {
			cycleVal = cleanCycle
		}
		if cycleVal == "" || strings.EqualFold(cycleVal, "all") || cycleVal == "كافة الدورات" {
			cycleVal = "أغسطس 2"
		}
		canonicalCycle := FormatCanonicalCycle(cycleVal)
		if canonicalCycle == "" {
			canonicalCycle = cycleVal
		}

		values := []interface{}{
			invNum,
			subNo,
			route,
			custName,
			address,
			meterNum,
			phone,
			blankIfZero(inv.PreviousReading),
			blankIfZero(inv.CurrentReading),
			blankIfZero(inv.Consumption),
			blankIfZero(inv.KwhPriceSnapshot),
			blankIfZero(inv.ConsumptionValue),
			blankIfZero(inv.FixedFeeSnapshot),
			blankIfZero(inv.TotalAmount),
			blankIfZero(inv.Arrears),
			blankIfZero(inv.TotalDue),
			blankIfZero(inv.PaidAmount),
			blankIfZero(inv.RemainingAmount),
			canonicalCycle,
		}

		for colIdx, val := range values {
			cell, _ := excelize.CoordinatesToCellName(colIdx+1, r)
			_ = f.SetCellValue(sheet, cell, val)
			_ = f.SetCellStyle(sheet, cell, cell, dataStyle)
		}
	}

	// Add Totals Summary Row
	totalRowNum := len(invoices) + 2
	_ = f.SetRowHeight(sheet, totalRowNum, 26)

	summaryValues := map[int]interface{}{
		1:  "الإجمالي العام",
		10: blankIfZero(sumConsumption),
		12: blankIfZero(sumConsumptionVal),
		13: blankIfZero(sumFixedFee),
		14: blankIfZero(sumTotalAmount),
		15: blankIfZero(sumArrears),
		16: blankIfZero(sumTotalDue),
		17: blankIfZero(sumPaid),
		18: blankIfZero(sumRemaining),
	}

	for colIdx := 1; colIdx <= len(headers); colIdx++ {
		cell, _ := excelize.CoordinatesToCellName(colIdx, totalRowNum)
		if val, exists := summaryValues[colIdx]; exists {
			_ = f.SetCellValue(sheet, cell, val)
		} else {
			_ = f.SetCellValue(sheet, cell, "-")
		}
		_ = f.SetCellStyle(sheet, cell, cell, totalStyle)
	}

	// Set optimal column widths
	colWidths := []float64{
		16, // 1: رقم الفاتورة
		14, // 2: رقم المشترك
		12, // 3: خط السير
		28, // 4: اسم المشترك
		20, // 5: العنوان
		16, // 6: رقم العداد
		16, // 7: رقم الهاتف
		14, // 8: القراءة السابقة
		14, // 9: القراءة الحالية
		15, // 10: الاستهلاك (ك.و)
		12, // 11: سعر الكيلو
		15, // 12: قيمة الاستهلاك
		14, // 13: رسوم الخدمة
		15, // 14: إجمالي الفاتورة
		14, // 15: المتأخرات
		16, // 16: إجمالي المستحق
		14, // 17: المسدد
		14, // 18: المتبقي
		16, // 19: الدورة الفوترية
	}

	for idx, width := range colWidths {
		colName, err := excelize.ColumnNumberToName(idx + 1)
		if err == nil {
			_ = f.SetColWidth(sheet, colName, colName, width)
		}
	}

	var buf bytes.Buffer
	if err := f.Write(&buf); err != nil {
		return nil, err
	}

	return buf.Bytes(), nil
}