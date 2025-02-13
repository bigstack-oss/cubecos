const switchOptions = [
  {
    id: 'lineNumbers',
    title: 'Line Numbers',
    trueValue: true,
    falseValue: false,
    value: true
  },
  {
    id: 'readOnly',
    title: 'Read Only',
    trueValue: false,
    falseValue: true,
    value: true
  }
];
const selectOptions = [
  {
    id: 'tabSize',
    title: 'Tab Size',
    options: ['2', '4', '6', '8'],
    value: 2
  },
  {
    id: 'mode',
    title: 'Language',
    options: ['javascript', 'xml', 'markdown', 'php', 'python', 'ruby'],
    value: 'javascript'
  },
  {
    id: 'theme',
    title: 'Select themes',
    options: [
      'default',
      'zenburn',
      'solarized',
      'rubyblue',
      'paraiso-dark',
      'midnight',
      'material',
      'hopscotch',
      'twilight'
    ],
    value: 'zenburn'
  }
];

const defaultValues = {
  basic: `const component = {
    name: 'Isomorphic',
    author: 'RedQ Team',
    website: 'https://isomorphic.redq.io/'
};`,
  javascript: `const component = {
    name: 'Isomorphic',
    author: 'RedQ Team',
    website: 'https://isomorphic.redq.io/'
};`,
  markdown: `# Isomorphic
###This is a RedQ Team production
[have a look](https://isomorphic.redq.io/)
  `,
  xml: `<isomprphic>
    <to>Tove</to>
    <name>Isomorphic</name>
    <author>RedQ Team</author>
    <website>isomorphic.redq.io</website>
</isomprphic>`,
  php: `<html>
 <head>
  <title> v</title>
 </head>
 <body>
 <h1>https://isomorphic.redq.io/</h1>
 <p>This is a RedQ Team production</p>
 <a href="https://isomorphic.redq.io/">visit ou site</a>
 </body>
</html>
`,
  python: `
print("Isomorphic")
print("This is a RedQ Team production")
print("visit us https://isomorphic.redq.io ")
`,
  ruby: `rint "Isomorphic"
print "This is a RedQ Team production"
print "visit us https://isomorphic.redq.io "
`
};

export { switchOptions, selectOptions, defaultValues };
