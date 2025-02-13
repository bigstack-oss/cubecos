import React from 'react';
import IntlMessages from '../../components/utility/intlMessages';

const Img1 = '/static/image/1.jpg';
const Img2 = '/static/image/2.jpg';
const Img3 = '/static/image/3.jpg';
const Img4 = '/static/image/4.jpg';
const Img5 = '/static/image/5.jpg';
const Img6 = '/static/image/6.jpg';
const Img7 = '/static/image/7.jpg';

const articles = [
  {
    id: 'a',
    timestamp: 811396800000,
    desc: <IntlMessages id="shuffle.descriptionOne" />,
    img: Img1,
  },
  {
    id: 'b',
    timestamp: 1108702800000,
    desc: <IntlMessages id="shuffle.descriptionTwo" />,
    img: Img2,
  },
  { 
    id: 'c', 
    timestamp: 1156564800000, 
    desc: <IntlMessages id="shuffle.descriptionThree" />, 
    img: Img3,
  },
  {
    id: 'd',
    timestamp: 1256443200000,
    desc: <IntlMessages id="shuffle.descriptionFour" />,
    img: Img4,
  },
  {
    id: 'e',
    timestamp: 1286942400000,
    desc: <IntlMessages id="shuffle.descriptionFive" />,
    img: Img5,
  },

  {
    id: 'f',
    timestamp: 1331697600000,
    desc: <IntlMessages id="shuffle.descriptionSix" />,
    img: Img6,
  },
  {
    id: 'g',
    timestamp: 1369800000000,
    desc: <IntlMessages id="shuffle.descriptionSeven" />,
    img: Img7,
  },
];

export default articles;
