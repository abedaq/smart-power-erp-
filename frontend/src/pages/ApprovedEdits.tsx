import React from 'react';
import { Navigate } from 'react-router-dom';

/**
 * @deprecated Removed as part of Milestone 4 (Tab Restructuring & Obsolete Tabs Removal).
 * Operations and reading revisions are integrated into Live Operations Log and Comprehensive Reports Hub.
 */
const ApprovedEdits: React.FC = () => {
  return <Navigate to="/invoices" replace />;
};

export default ApprovedEdits;
