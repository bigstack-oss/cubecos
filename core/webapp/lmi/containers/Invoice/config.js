const localDataName = 'mateInvoice';
const orderStatusOptions = ['Pending', 'Shipped', 'Delivered'];

const fakedata = [
	{
		key: 1,
		id: '1518713981654',
		number: '#1231',
		orderStatus: 'Shipped',
		orderDate: 1518849188360,
		currency: '$',
		billTo: 'REDQ Inc.',
		billToAddress:
			'redq@company.com\n\n405 Mulberry Rd, Mc Grady, \nNC, 28649 \n\nFax: +0(863) 228-7064 \nPhone: +(740) 927-9284',
		billFrom: 'Pineapple Inc.',
		billFromAddress:
			'pineapple@company.com\n\n86781 547th Ave, Osmond, \nNE, 68765 \n\nPhone: +(402) 748-3970',
		invoiceList: [
			{
				key: 1,
				itemName: 'A box of happiness',
				costs: 200,
				qty: 14,
				price: 2800,
			},
			{ key: 2, itemName: 'Unicorn Tears', costs: 500, qty: 14, price: 7000 },
			{ key: 3, itemName: 'Rainbow Machine', costs: 700, qty: 5, price: 3500 },
		],
		subTotal: 13300,
		vatRate: 10,
		vatPrice: 1330,
		totalCost: 14630,
	},
	{
		key: 2,
		id: '1518713981655',
		number: '#1232',
		orderStatus: 'Pending',
		orderDate: 1518849188360,
		currency: '$',
		billTo: 'REDQ Inc.',
		billToAddress:
			'redq@company.com\n\n405 Mulberry Rd, Mc Grady, \nNC, 28649 \n\nFax: +0(863) 228-7064 \nPhone: +(740) 927-9284',
		billFrom: 'Pineapple Inc.',
		billFromAddress:
			'pineapple@company.com\n\n86781 547th Ave, Osmond, \nNE, 68765 \n\nPhone: +(402) 748-3970',
		invoiceList: [
			{
				key: 1,
				itemName: 'A box of happiness',
				costs: 200,
				qty: 14,
				price: 2800,
			},
			{ key: 2, itemName: 'Unicorn Tears', costs: 500, qty: 14, price: 7000 },
			{ key: 3, itemName: 'Rainbow Machine', costs: 700, qty: 5, price: 3500 },
		],
		subTotal: 13300,
		vatRate: 10,
		vatPrice: 1330,
		totalCost: 14630,
	},
	{
		key: 3,
		id: '1518713981656',
		number: '#1233',
		orderStatus: 'Delivered',
		orderDate: 1518849188360,
		currency: '$',
		billTo: 'REDQ Inc.',
		billToAddress:
			'redq@company.com\n\n405 Mulberry Rd, Mc Grady, \nNC, 28649 \n\nFax: +0(863) 228-7064 \nPhone: +(740) 927-9284',
		billFrom: 'Pineapple Inc.',
		billFromAddress:
			'pineapple@company.com\n\n86781 547th Ave, Osmond, \nNE, 68765 \n\nPhone: +(402) 748-3970',
		invoiceList: [
			{
				key: 1,
				itemName: 'A box of happiness',
				costs: 200,
				qty: 14,
				price: 2800,
			},
			{ key: 2, itemName: 'Unicorn Tears', costs: 500, qty: 14, price: 7000 },
			{ key: 3, itemName: 'Rainbow Machine', costs: 700, qty: 5, price: 3500 },
		],
		subTotal: 13300,
		vatRate: 10,
		vatPrice: 1330,
		totalCost: 14630,
	},
];
const newInvoice = {
	orderStatus: 'Pending',
	orderDate: new Date().getTime(),
	currency: '$',
	billTo: '',
	billToAddress: '',
	billFrom: '',
	billFromAddress: '',
	invoiceList: [
		{
			key: 1,
			itemName: '',
			costs: 0,
			qty: 0,
			price: 0,
		},
	],
	subTotal: 0,
	vatRate: 10,
	vatPrice: 0,
	totalCost: 0,
};
const createDemoData = () => {
	return fakedata;
};

export {
	fakedata,
	createDemoData,
	localDataName,
	newInvoice,
	orderStatusOptions,
};
