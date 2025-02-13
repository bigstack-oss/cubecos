import React from 'react';
import { TableViews } from '../../Tables/antTables';
import Button from '../../../components/uielements/button';
import InvoicePageWrapper from './invoice.style';

const Table = TableViews.SimpleView;
const columns = [
  {
    title: '#',
    dataIndex: 'index',
    key: 'index',
    width: '5%'
  },
  {
    title: 'Item Name',
    dataIndex: 'itemname',
    key: 'itemname',
    width: '65%',
    className: 'itemName'
  },
  {
    title: 'Costs',
    dataIndex: 'costs',
    key: 'costs',
    width: '10%'
  },
  {
    title: 'Qty',
    dataIndex: 'quantity',
    key: 'quantity',
    width: '10%'
  },
  {
    title: 'Price',
    dataIndex: 'price',
    key: 'price',
    width: '10%'
  }
];

const data = [
  {
    key: '1',
    index: '1',
    itemname: 'A box of happiness',
    costs: 200,
    quantity: 14,
    price: '$2800'
  },
  {
    key: '2',
    index: '2',
    itemname: 'Unicorn Tears',
    costs: 500,
    quantity: 14,
    price: '$7000'
  },
  {
    key: '3',
    index: '3',
    itemname: 'Rainbow Machine',
    costs: 700,
    quantity: 5,
    price: '$3500'
  }
];

export default class Invoice extends React.Component {
  state = {
    pagination: false
  };

  render() {
    return (
      <InvoicePageWrapper className="isoInvoicePageWrapper">
        <div className="isoPageHeader">
          <h1 className="isoPageTitle">Invoice</h1>
          <Button type="primary" icon="printer">
            Print Invoice
          </Button>
        </div>

        <div className="isoPageContent">
          <div className="isoOrderInfo">
            <div className="isoLeftSideContent">
              <h3 className="isoTitle">Invoice Info</h3>
              <span className="isoInvoiceNumber">#1942784</span>
            </div>

            <div className="isoRightSideContent">
              <p>
                Order Status: <span className="orderStatus">Pending</span>
              </p>
              <p>
                Order date: <span className="orderDate">June 23, 2017</span>
              </p>
            </div>
          </div>

          <div className="isoBillingInformation">
            <div className="isoLeftSideContent">
              <h3 className="isoTitle">Bill From</h3>

              <p className="isoNameEmail">
                <span className="isoName">REDQ Inc.</span>
                <span className="isoEmail">redq@company.com</span>
              </p>

              <address>
                405 Mulberry Rd, Mc Grady, <br />
                NC, 28649 <br />
                <br />
                <span className="fax">Fax: </span>+0(863) 228-7064 <br />
                <span className="phone">Phone: </span>+(740) 927-9284
              </address>
            </div>

            <div className="isoRightSideContent">
              <h3 className="isoTitle">Bill To</h3>

              <p className="isoNameEmail">
                <span className="isoName">Pineapple Inc.</span>
                <span className="isoEmail">pineapple@company.com</span>
              </p>

              <address>
                86781 547th Ave, Osmond, <br />
                NE, 68765 <br />
                <br />
                <span className="phone">Phone: </span>+(402) 748-3970
              </address>
            </div>
          </div>

          <div className="isoInvoiceTable">
            <div className="isoSimpleTable">
              <Table {...this.state} columns={columns} dataSource={data} />
            </div>
            <div className="isoTotalBill">
              <p>
                Sub-total : <span>$13300</span>
              </p>
              <p>
                Vat : <span>$700</span>
              </p>
              <h3>
                Grand Total : <span>$14000</span>
              </h3>
            </div>
          </div>

          <div className="isoButtonWrapper">
            <Button type="primary">Send Invoice</Button>
            <Button icon="printer">Print</Button>
          </div>
        </div>
      </InvoicePageWrapper>
    );
  }
}
