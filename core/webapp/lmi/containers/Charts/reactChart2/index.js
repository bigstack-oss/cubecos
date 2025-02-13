import React from 'react';
import { Row, Col } from 'antd';
import Async from '../../../helpers/asyncComponent';
import basicStyle from '../../../config/basicStyle';
import ChartWrapper from '../chart.style';

const Doughnut = props => (
  <ChartWrapper>
    <Async
      load={import(/* webpackChunkName: "ReactChart2-Doughnut" */ './components/doughnut/doughnut')}
      componentProps={props}
    />
  </ChartWrapper>
);
const DynamicDoughnut = props => (
  <ChartWrapper>
    <Async
      load={import(/* webpackChunkName: "ReactChart2-dynamic-doughnut" */ './components/dynamic-doughnut/dynamic-doughnut')}
      componentProps={props}
    />
  </ChartWrapper>
);
const Pie = props => (
  <ChartWrapper>
    <Async
      load={import(/* webpackChunkName: "ReactChart2-pie" */ './components/pie/pie')}
      componentProps={props}
    />
  </ChartWrapper>
);
const Line = props => (
  <ChartWrapper>
    <Async
      load={import(/* webpackChunkName: "ReactChart2-line" */ './components/line/line')}
      componentProps={props}
    />
  </ChartWrapper>
);
const Bar = props => (
  <ChartWrapper>
    <Async
      load={import(/* webpackChunkName: "ReactChart2-bar" */ './components/bar/bar')}
      componentProps={props}
    />
  </ChartWrapper>
);
const HorizontalBar = props => (
  <ChartWrapper>
    <Async
      load={import(/* webpackChunkName: "ReactChart2-horizontalBar" */ './components/horizontalBar/horizontalBar')}
      componentProps={props}
    />
  </ChartWrapper>
);
const Radar = props => (
  <ChartWrapper>
    <Async
      load={import(/* webpackChunkName: "ReactChart2-radar" */ './components/radar/radar')}
      componentProps={props}
    />
  </ChartWrapper>
);
const Polar = props => (
  <ChartWrapper>
    <Async
      load={import(/* webpackChunkName: "ReactChart2-polar" */ './components/polar/polar')}
      componentProps={props}
    />
  </ChartWrapper>
);
const Bubble = props => (
  <ChartWrapper>
    <Async
      load={import(/* webpackChunkName: "ReactChart2-bubble" */ './components/bubble/bubble')}
      componentProps={props}
    />
  </ChartWrapper>
);
const MixedData = props => (
  <ChartWrapper>
    <Async
      load={import(/* webpackChunkName: "ReactChart2-mix" */ './components/mix/mix')}
      componentProps={props}
    />
  </ChartWrapper>
);
const RandomizedDataLine = props => (
  <ChartWrapper>
    <Async
      load={import(/* webpackChunkName: "ReactChart2-randomizedLine" */ './components/randomizedLine/randomizedLine')}
      componentProps={props}
    />
  </ChartWrapper>
);
const PageHeader = props => (
  <Async
    load={import(/* webpackChunkName: "ReactChart2-pageHeader" */ '../../../components/utility/pageHeader')}
    componentProps={props}
  />
);
const Box = props => (
  <ChartWrapper>
    <Async
      load={import(/* webpackChunkName: "ReactChart2-box" */ '../../../components/utility/box')}
      componentProps={props}
    />
  </ChartWrapper>
);
const LayoutWrapper = props => (
  <ChartWrapper>
    <Async
      load={import(/* webpackChunkName: "ReactChart2-layoutWrapper" */ '../../../components/utility/layoutWrapper')}
      componentProps={props}
    />
  </ChartWrapper>
);
const ContentHolder = props => (
  <ChartWrapper>
    <Async
      load={import(/* webpackChunkName: "ReactChart2-contentHolder" */ '../../../components/utility/contentHolder')}
      componentProps={props}
    />
  </ChartWrapper>
);
// const basicStyle = props =>
//   <Async
//     load={import(/* webpackChunkName: "ReactChart2-basicStyle" */ "../../../config/basicStyle")}
//     componentProps={props}
//   />;

class ReactChart2 extends React.Component {
  render() {
    const { rowStyle, colStyle, gutter } = basicStyle;
    return (
      <LayoutWrapper className="isoMapPage">
        <PageHeader>React Charts 2</PageHeader>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} xs={24} style={colStyle}>
            <Box title="Doughnut">
              <ContentHolder>
                <Doughnut />
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} xs={24} style={colStyle}>
            <Box title="Dynamicly refreshed Doughnut">
              <ContentHolder>
                <DynamicDoughnut />
              </ContentHolder>
            </Box>
          </Col>
        </Row>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} xs={24} style={colStyle}>
            <Box title="Pie">
              <ContentHolder>
                <Pie />
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} xs={24} style={colStyle}>
            <Box title="Line">
              <ContentHolder>
                <Line />
              </ContentHolder>
            </Box>
          </Col>
        </Row>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} xs={24} style={colStyle}>
            <Box title="Bar (custom size)">
              <ContentHolder>
                <Bar />
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} xs={24} style={colStyle}>
            <Box title="Horizontal Bar Example">
              <ContentHolder>
                <HorizontalBar />
              </ContentHolder>
            </Box>
          </Col>
        </Row>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} xs={24} style={colStyle}>
            <Box title="Radar">
              <ContentHolder>
                <Radar />
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} xs={24} style={colStyle}>
            <Box title="Polar">
              <ContentHolder>
                <Polar />
              </ContentHolder>
            </Box>
          </Col>
        </Row>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} xs={24} style={colStyle}>
            <Box title="Bubble">
              <ContentHolder>
                <Bubble />
              </ContentHolder>
            </Box>
          </Col>
          <Col md={12} xs={24} style={colStyle}>
            <Box title="Mixed Data">
              <ContentHolder>
                <MixedData />
              </ContentHolder>
            </Box>
          </Col>
        </Row>
        <Row style={rowStyle} gutter={gutter} justify="start">
          <Col md={12} xs={24} style={colStyle}>
            <Box title="Random Animated">
              <ContentHolder>
                <RandomizedDataLine />
              </ContentHolder>
            </Box>
          </Col>
        </Row>
      </LayoutWrapper>
    );
  }
}

export default ReactChart2;
