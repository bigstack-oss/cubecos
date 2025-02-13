import Document, { Head, Main, NextScript } from 'next/document';
import flush from 'styled-jsx/server';
import { ServerStyleSheet } from 'styled-components';
import Helmet from 'react-helmet';

export default class MyDocument extends Document {
  static async getInitialProps(...args) {
    const documentProps = await super.getInitialProps(...args);
    const styles = flush();
    return { ...documentProps, helmet: Helmet.renderStatic(), styles };
  }
  // should render on <html>
  get helmetHtmlAttrComponents() {
    return this.props.helmet.htmlAttributes.toComponent();
  }

  // should render on <body>
  get helmetBodyAttrComponents() {
    return this.props.helmet.bodyAttributes.toComponent();
  }

  // should render on <head>
  get helmetHeadComponents() {
    return Object.keys(this.props.helmet)
      .filter(el => el !== 'htmlAttributes' && el !== 'bodyAttributes')
      .map(el => this.props.helmet[el].toComponent());
  }

  get helmetJsx() {
    return (
      <Helmet
        htmlAttributes={{ lang: 'en' }}
        title="Cube"
        meta={[
          { name: 'viewport', content: 'width=device-width, initial-scale=1' }
        ]}
      />
    );
  }
  render() {
    const sheet = new ServerStyleSheet();
    const main = sheet.collectStyles(<Main />);
    const styleTags = sheet.getStyleElement();
    return (
      <html {...this.helmetHtmlAttrComponents}>
        <Head>
          {this.helmetJsx}
          {this.helmetHeadComponents}
          <style>{`body { margin: 0 }`}</style>
          {/*
          <link
            rel="stylesheet"
            href="//cdnjs.cloudflare.com/ajax/libs/antd/3.20.0/antd.min.css"
          />
          */}
          <link rel="stylesheet" href="/static/css/antd.min.css" />
          <link rel="stylesheet" href="/static/css/ionicons.min.css" />
          <link rel="stylesheet" href="/static/css/global.css" />
          <link rel="stylesheet" href="/static/css/themify-icons.css" />
          {/*
          <link href="https://fonts.googleapis.com/css?family=Roboto:100,300,400,500,700" rel="stylesheet" async />
          <link rel="stylesheet" href="https://unpkg.com/react-instantsearch-theme-algolia@4.0.0/style.min.css" />
          <link rel="stylesheet" href="https://unpkg.com/leaflet@1.2.0/dist/leaflet.css"
           integrity="sha512-M2wvCLH6DSRazYeZRIm1JnYyh22purTM+FDB5CsyxtQJYeKq83arPe5wgbNmcFXGqiSH2XR8dT/fJISVA1r/zQ=="
           crossOrigin="" async />
          */}
          <link rel="stylesheet" href="/static/css/roboto.css" />
          <link rel="stylesheet" href="/static/css/style.min.css" />
          <link rel="stylesheet" href="/static/css/leaflet.css" />
          <link rel="icon" type="image/png" sizes="32x32" href="/static/image/icons/favicon-32x32.png"/>
          <script src="/static/env.js"></script>
          {styleTags}
        </Head>
        <body {...this.helmetBodyAttrComponents}>
          {main}
          <NextScript />
        </body>
      </html>
    );
  }
}
