const demoUsers = [
  {
    name: 'Alis Reah',
    dob: '17-Jun-1998',
    mobileNo: '8432025739',
    gender: 'Male',
    language: 'Mongolian',
    profileImageUrl:
      'https://thumb1.shutterstock.com/display_pic_with_logo/3671573/723643036/stock-photo-business-man-a-black-man-button-his-jacket-on-a-light-background-723643036.jpg'
  },
  {
    name: 'Tara Bonnin',
    dob: '09-Mar-1997',
    mobileNo: '0337555648',
    gender: 'Male',
    language: 'Ndebele',
    profileImageUrl:
      'https://thumb7.shutterstock.com/display_pic_with_logo/3671573/723077854/stock-photo-business-man-black-man-in-a-white-shirt-on-isolated-background-723077854.jpg'
  },
  {
    name: 'Jackquelin Quartermaine',
    dob: '27-Jan-1991',
    mobileNo: '4605287981',
    gender: 'Male',
    language: 'Maltese',
    profileImageUrl:
      'https://thumb7.shutterstock.com/display_pic_with_logo/156673/674799844/stock-photo-satisfying-call-young-black-businessman-in-casual-has-mobile-phone-talk-in-modern-white-office-674799844.jpg'
  },
  {
    name: 'Carina Fruen',
    dob: '13-Sep-1994',
    mobileNo: '9572447092',
    gender: 'Male',
    language: 'Sotho',
    profileImageUrl:
      'https://thumb1.shutterstock.com/display_pic_with_logo/76219/207792106/stock-photo-handsome-businessman-frowning-at-camera-in-his-office-207792106.jpg'
  },
  {
    name: 'Juditha Simla',
    dob: '13-Feb-2000',
    mobileNo: '3501026382',
    gender: 'Male',
    language: 'Swedish',
    profileImageUrl:
      'https://thumb9.shutterstock.com/display_pic_with_logo/2670070/503436898/stock-photo--african-american-businessman-smiling-503436898.jpg'
  },
  {
    name: 'Felicity Shorbrook',
    dob: '31-Jan-1993',
    mobileNo: '1212498836',
    gender: 'Female',
    language: 'Spanish',
    profileImageUrl:
      'https://thumb9.shutterstock.com/display_pic_with_logo/2717350/741158365/stock-photo-smiling-black-businesswoman-with-arms-crossed-741158365.jpg'
  },
  {
    name: "Hewet O'Kelly",
    dob: '28-Mar-2000',
    mobileNo: '3084621977',
    gender: 'Male',
    language: 'Tsonga',
    profileImageUrl:
      'https://thumb7.shutterstock.com/display_pic_with_logo/2181548/474753844/stock-photo-handsome-afro-american-businessman-in-classic-suit-is-using-a-laptop-and-smiling-while-working-in-474753844.jpg'
  },
  {
    name: 'Zondra Kulic',
    dob: '06-Apr-1993',
    mobileNo: '5726784596',
    gender: 'Male',
    language: 'Burmese',
    profileImageUrl:
      'https://thumb9.shutterstock.com/display_pic_with_logo/818215/403315558/stock-photo-confident-black-business-man-in-a-stylish-suit-standing-with-folded-arms-on-a-rooftop-of-n-office-403315558.jpg'
  },
  {
    name: 'Trixie Northcliffe',
    dob: '02-Aug-1991',
    mobileNo: '2956829807',
    gender: 'Female',
    language: 'Arabic',
    profileImageUrl:
      'https://thumb7.shutterstock.com/display_pic_with_logo/818215/552201991/stock-photo-beautiful-young-grinning-professional-black-woman-in-office-with-eyeglasses-folded-arms-and-552201991.jpg'
  },
  {
    name: 'Dorena Sherry',
    dob: '22-Apr-1992',
    mobileNo: '9429692135',
    gender: 'Male',
    language: 'Bosnian',
    profileImageUrl:
      'https://thumb7.shutterstock.com/display_pic_with_logo/818215/552201991/stock-photo-beautiful-young-grinning-professional-black-woman-in-office-with-eyeglasses-folded-arms-and-552201991.jpg'
  },
  {
    name: 'Gerek MacGuffog',
    dob: '26-Feb-1995',
    mobileNo: '2886843121',
    gender: 'Female',
    language: 'Dari',
    profileImageUrl:
      'https://thumb1.shutterstock.com/display_pic_with_logo/1294/139687573/stock-photo-portrait-of-a-happy-business-woman-smiling-139687573.jpg'
  },
  {
    name: 'Cal Leggitt',
    dob: '29-Jul-2000',
    mobileNo: '9588591899',
    gender: 'Female',
    language: 'Icelandic',
    profileImageUrl:
      'https://thumb1.shutterstock.com/display_pic_with_logo/751597/262378913/stock-photo-portrait-of-a-young-african-american-business-woman-black-people-262378913.jpg'
  },
  {
    name: 'Garfield Swinyard',
    dob: '09-Mar-2000',
    mobileNo: '7960813167',
    gender: 'Male',
    language: 'Swati',
    profileImageUrl:
      'https://thumb7.shutterstock.com/display_pic_with_logo/102/102,1266999999,1/stock-photo-a-happy-black-business-man-with-people-in-the-background-47419153.jpg'
  },
  {
    name: 'Lorita Robken',
    dob: '18-Dec-1994',
    mobileNo: '5450953445',
    gender: 'Male',
    language: 'Malayalam',
    profileImageUrl:
      'https://thumb9.shutterstock.com/display_pic_with_logo/698308/567772042/stock-photo-headshot-of-successful-smiling-cheerful-african-american-businessman-executive-stylish-company-567772042.jpg'
  },
  {
    name: 'Cecelia Tigner',
    dob: '29-Sep-1999',
    mobileNo: '8002850483',
    gender: 'Male',
    language: 'Dutch',
    profileImageUrl:
      'https://thumb1.shutterstock.com/display_pic_with_logo/270058/116922589/stock-photo-peaceful-african-american-businessman-in-office-116922589.jpg'
  }
];
/*
const createDemoUsers = () => {
  demoUsers.forEach(user => fsProps.usersCollections.add(user));
};
const createDemoChatrooms = users => {
  for (let i = 0; i < users.length; i++) {
    for (let j = i + 1; j < users.length; j++) {
      const key = firebase
        .database()
        .ref()
        .push().key;
      const revKey = reverseString(key);
      const docI = fsProps.chatroomCollections.doc(key);
      const docJ = fsProps.chatroomCollections.doc(revKey);
      docI.set({
        id: key,
        userId: users[i].id,
        otherUserId: users[j].id,
        otherUserInfo: users[j],
        lastMessage: '',
        lastMessageTime: 0
      });
      docJ.set({
        id: key,
        reverse: true,
        userId: users[j].id,
        otherUserId: users[i].id,
        otherUserInfo: users[i],
        lastMessage: '',
        lastMessageTime: 0
      });
    }
  }
}
*/
export { demoUsers };
