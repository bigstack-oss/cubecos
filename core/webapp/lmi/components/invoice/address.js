import React from 'react';

export default ({ companyName, companyAddress }) => (
  <div>
    <p className="NameEmail">
      <span className="Name">{companyName}</span>
      <span className="Email" style={{ whiteSpace: 'pre-line' }}>
        {companyAddress}
      </span>
    </p>
  </div>
);
