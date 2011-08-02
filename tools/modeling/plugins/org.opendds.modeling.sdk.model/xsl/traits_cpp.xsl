<xsl:stylesheet version='1.0'
     xmlns:xsl='http://www.w3.org/1999/XSL/Transform'
     xmlns:xsi='http://www.w3.org/2001/XMLSchema-instance'
     xmlns:xmi='http://www.omg.org/XMI'
     xmlns:lut='http://www.opendds.org/modeling/schemas/Lut/1.0'
     xmlns:opendds='http://www.opendds.org/modeling/schemas/OpenDDS/1.0'
     xmlns:generator='http://www.opendds.org/modeling/schemas/Generator/1.0'>
  <!--
    ** $Id$
    **
    ** Generate C++ implementation code.
    **
    ** @TODO - check string management.
    ** @TODO - determine how to set the transport addresses.
    **
    -->
<xsl:include href="common.xsl"/>

<xsl:output method="text"/>
<xsl:strip-space elements="*"/>

<!-- Extract values once. -->
<xsl:variable name="model" select="document(/generator:CodeGen/source/@name)/opendds:OpenDDSModel"/>
<xsl:variable name="modelname" select="$model/@name"/>
<xsl:variable name="instances" select="//instance"/>
<xsl:variable name="tcp-transport-enum" 
            select="'OpenDDS::Model::Transport::Type::tcp'"/>
<xsl:variable name="multicast-transport-enum"
            select="'OpenDDS::Model::Transport::Type::multicast'"/>
<xsl:variable name="udp-transport-enum"
            select="'OpenDDS::Model::Transport::Type::udp'"/>

<!-- process the entire genfile document to produce the C++ code. -->
<xsl:template match="/">
  <xsl:value-of select="concat('#include &quot;', $modelname, 'Traits.h&quot;', 
                               $newline)"/>
  <xsl:text>
#include "dds/DCPS/transport/framework/TransportRegistry.h"
#include "dds/DCPS/transport/framework/TransportExceptions.h"
#include "dds/DCPS/transport/tcp/TcpInst.h"
#include "dds/DCPS/transport/tcp/TcpInst_rch.h"
#include "dds/DCPS/transport/multicast/MulticastInst.h"
#include "dds/DCPS/transport/multicast/MulticastInst_rch.h"
#include "dds/DCPS/transport/udp/UdpInst.h"
#include "dds/DCPS/transport/udp/UdpInst_rch.h"
#include &lt;model/TransportDirectives.h&gt;

#include &lt;stdexcept&gt;
</xsl:text>
  <xsl:apply-templates select="$model"/>
</xsl:template>

<!-- For packages containing a DCPS lib, output a namespace -->
<xsl:template match="packages[.//libs[@xsi:type='opendds:DcpsLib']]">
  <xsl:value-of select="concat('namespace ', @name, ' {', $newline)"/>
  <xsl:apply-templates/>
  <xsl:value-of select="concat('}', $newline)"/>
</xsl:template>

<!-- For a DCPS lib, output a namespace, then each instance -->
<xsl:template match="libs[@xsi:type='opendds:DcpsLib']">
  <xsl:value-of select="concat('namespace ', @name, ' {', $newline)"/>
  <xsl:for-each select="$instances">
    <xsl:call-template name="output-instance"/>
  </xsl:for-each>
  <xsl:value-of select="concat('}', $newline)"/>
</xsl:template>

<!-- Output class method definitions for an instance.
     These are uniquely qualified by their containing namespace.
  -->
<xsl:template name="output-instance">
  <xsl:variable name="Instname">
    <xsl:call-template name="capitalize">
      <xsl:with-param name="value" select="@name"/>
    </xsl:call-template>
  </xsl:variable>
  <xsl:variable name="classname" select="concat($Instname, $modelname, 'Traits')"/>

  <xsl:value-of select="concat($classname, '::', $classname,
      '() {', $newline)"/>
  <xsl:variable name="transportInsts" select="//transports/transport"/>
  <xsl:for-each select="$transportInsts">
    <xsl:variable name="varname" select="concat(@name, '_inst')"/>
    <xsl:variable name="transport-type" 
        select="translate(
                   substring-before(
                       substring-after(@xsi:type, ':'), 'Transport'),
                   $upper, $lower)"/>
    <xsl:variable name="transport-class">
      <xsl:text>OpenDDS::DCPS::</xsl:text>
      <xsl:call-template name="capitalize">
        <xsl:with-param name="value" select="$transport-type"/>
      </xsl:call-template>
      <xsl:text>Inst</xsl:text>
    </xsl:variable>
    <xsl:value-of select="concat(
        '  OpenDDS::DCPS::TransportInst_rch ', $varname, ' = ', $newline,
        '      TheTransportRegistry->get_inst(&quot;', @name, '&quot;);', 
        $newline)"/>
    <xsl:value-of select="concat(
        '  if (', $varname, '.is_nil()) {', 
        $newline
    )"/>
    <xsl:value-of select="concat(
        '    ', $varname, ' = ', 
        'TheTransportRegistry->create_inst(&quot;', @name, '&quot;, ',
        '&quot;', $transport-type, '&quot;);', $newline
    )"/>
    <xsl:text>    // Ignoring actual transport configuration 
</xsl:text>
    <xsl:value-of select="concat(
        '    ', $transport-class, '_rch child_inst =', $newline,
        '        OpenDDS::DCPS::static_rchandle_cast&lt;', $transport-class, 
        '&gt;(', $varname, ');', $newline)"/>
    <xsl:text>  }

</xsl:text>
  </xsl:for-each>
  <xsl:if test="config/transportRef">
    <xsl:text>  // Associate TransportInsts with TransportConfigs
</xsl:text>
  </xsl:if>
  <xsl:for-each select="config">
    <xsl:variable name="config-varname" select="concat(@name, '_cfg')"/>
    <xsl:value-of select="concat(
        '  OpenDDS::DCPS::TransportConfig_rch ', $config-varname, ' =', $newline,
        '      TheTransportRegistry->create_config(&quot;', @name, 
        '&quot;);', $newline
    )"/>
    <xsl:for-each select="transportRef">
      <xsl:variable name="ref-varname" select="concat(
          $transportInsts[@xmi:id = current()/@transport]/@name, '_inst')"/>
      <xsl:value-of select="concat('  ', $config-varname, 
                                 '->instances_.push_back(', $ref-varname, 
                                 ');', $newline
      )"/>
    </xsl:for-each>
  </xsl:for-each>
<xsl:text>
}

</xsl:text>

  <xsl:value-of select="concat($classname, '::~', $classname,
      '() { }', $newline, $newline)"/>
  <!--
  <xsl:value-of select="concat('void ', $classname)"/>
  <xsl:text>::transport_config(OpenDDS::DCPS::TransportIdType id) {
</xsl:text>
      <xsl:text>  OpenDDS::DCPS::TransportInst_rch config;
  ACE_TString transport_type;

  try {
    config = TheTransportFactory->get_configuration(id);
  } catch (OpenDDS::DCPS::Transport::NotConfigured&amp;) {
    // Create configuration for this transport ID
    switch (id) {
</xsl:text>
      <xsl:apply-templates/>
      <xsl:text>      default:
        throw std::runtime_error("Invalid transport ID in configuration");
    };
  }
</xsl:text>
<xsl:text>  // Create the impl
  OpenDDS::DCPS::TransportImpl_rch impl = TheTransportFactory->obtain(id);
  if (!impl.in()) {
    impl = TheTransportFactory->create_transport_impl(id, true);
  }
}
</xsl:text>
-->

</xsl:template>

<!-- Transports for the instance, output case which creates and
     registers configuration... -->
<xsl:template match="transport">
  <xsl:variable name="type">
    <xsl:call-template name="transport-type"/>
  </xsl:variable>

  <xsl:variable name="label" select="../transportOffset/@value + @transportIndex"/>
  <xsl:value-of select="concat('      case ', $label, ':', $newline)"/>
  <xsl:call-template name="loadTransportLibraries"/>
  <xsl:value-of select="concat('        transport_type = ACE_TEXT(&quot;', $type, '&quot;);', $newline)"/>
  <xsl:text>        config = TheTransportFactory->create_configuration(id, transport_type);
</xsl:text>
  <xsl:apply-templates/>
  <xsl:value-of select="concat('        break;', $newline, $newline)"/>
</xsl:template>

<xsl:template match="swap_bytes">
  <xsl:value-of select="concat('          config->swap_bytes_ = ', 
                               @value, ';', $newline)"/>
</xsl:template>

<!-- Output general configuration settings -->
<xsl:template match="queue_messages_per_pool 
                   | queue_initial_pools
                   | max_packet_size
                   | max_samples_per_packet
                   | optimum_packet_size
                   | thread_per_connection
                   | datalink_release_delay
                   | datalink_control_chunks">
  <xsl:value-of select="concat('          config->', name(), '_ = ', 
                               @value, ';', $newline)"/>
</xsl:template>

<!-- Handle TCP-specific configuration parameters -->
<xsl:template match="TCPTransport[*]">
  <xsl:text>        {
          OpenDDS::DCPS::TcpInst* specific_config =
              (OpenDDS::DCPS::TcpInst*) config.in();
</xsl:text>
  <xsl:apply-templates/>
  <xsl:text>        }
</xsl:text>
</xsl:template>

<!-- Handle Multicast-specific configuration parameters -->
<xsl:template match="MulticastTransport[*]">
  <xsl:text>        {
          OpenDDS::DCPS::MulticastInst* specific_config =
              (OpenDDS::DCPS::MulticastInst*) config.in();
</xsl:text>
  <xsl:apply-templates/>
  <xsl:text>        }
</xsl:text>
</xsl:template>

<!-- Handle UDP-specific configuration parameters -->
<xsl:template match="UDPTransport[*]">
  <xsl:text>        {
          OpenDDS::DCPS::UdpInst* specific_config =
              (OpenDDS::DCPS::UdpInst*) config.in();
</xsl:text>
  <xsl:apply-templates/>
  <xsl:text>        }
</xsl:text>
</xsl:template>

<!-- Output IP address conversion for local address -->
<xsl:template match="local_address_str">
  <xsl:variable name="value">
    <xsl:call-template name="str-value"/>
  </xsl:variable>
  <xsl:value-of select="concat('          specific_config->local_address_ = ',
                               'ACE_INET_Addr(&quot;', $value, '&quot;)',
                               ';', $newline)"/>
</xsl:template>

<!-- Output type-specific configuration settings -->
<xsl:template match="enable_nagle_algorithm
                   | conn_retry_initial_delay
                   | conn_retry_backoff_multiplier
                   | conn_retry_attempts
                   | max_output_pause_period
                   | passive_reconnect_duration
                   | passive_connect_duration
                   | default_to_ipv6
                   | port_offset
                   | reliable
                   | syn_backoff
                   | syn_interval
                   | syn_timeout
                   | nak_depth
                   | ttl
                   | rcv_buffer_size
                   | nak_interval
                   | nak_timeout">

  <xsl:value-of select="concat('          specific_config->', name(),  '_ = ',
                               @value, ';', $newline)"/>
</xsl:template>

<!-- Output IP address conversion for group address -->
<xsl:template match="group_address">
  <xsl:variable name="value">
    <xsl:call-template name="str-value"/>
  </xsl:variable>
  <xsl:value-of select="concat('          specific_config->group_address_ = ',
                               'ACE_INET_Addr(&quot;', $value, '&quot;)',
                               ';', $newline)"/>
</xsl:template>

<!-- Map subelements to transport type string -->
<xsl:template name="transport-type">
  <xsl:choose>
    <xsl:when test="TCPTransport">tcp</xsl:when>
    <xsl:when test="MulticastTransport">multicast</xsl:when>
    <xsl:when test="UDPTransport">udp</xsl:when>
    <xsl:when test="*">
      <xsl:message>Unknown transport_type</xsl:message>
    </xsl:when>
  </xsl:choose>
</xsl:template>

<xsl:template name="loadTransportLibraries">
  <xsl:variable name="type-enum">
    <xsl:call-template name="transport-type-enum"/>
  </xsl:variable>
  <!-- if its not a TCP transport, load it anyway for BIT -->
  <xsl:if test="$type-enum != $tcp-transport-enum">
    <xsl:text>#if !defined (DDS_HAS_MINIMUM_BIT)
        if (TheServiceParticipant->get_BIT()) {
</xsl:text>
    <xsl:value-of select="concat('          loadTransportLibraryIfNeeded(',
                                 $tcp-transport-enum, ');', $newline)"/>
    <xsl:text>        }
#endif
</xsl:text>
  </xsl:if>
  <xsl:value-of select="concat('        loadTransportLibraryIfNeeded(',
                               $type-enum, ');', $newline)"/>
</xsl:template>

<xsl:template name="transport-type-enum">
  <xsl:choose>
    <xsl:when test="TCPTransport">
      <xsl:value-of select="$tcp-transport-enum"/>
    </xsl:when>
    <xsl:when test="MulticastTransport">
      <xsl:value-of select="$multicast-transport-enum"/>
    </xsl:when>
    <xsl:when test="UDPTransport">
      <xsl:value-of select="$udp-transport-enum"/>
    </xsl:when>
    <xsl:when test="*">
      <xsl:message>OpenDDS::Model::Transport::Type::unknown</xsl:message>
    </xsl:when>
  </xsl:choose>
</xsl:template>
<!-- Handle string values with and without quotes -->
<xsl:template name="str-value">
  <xsl:param name="value" select="@value"/>
  <xsl:choose>
    <xsl:when test="starts-with($value, '&quot;')">
      <xsl:value-of select="substring-before(substring-after($value, '&quot;'), '&quot;')"/>
    </xsl:when>
    <xsl:otherwise>
      <xsl:value-of select="$value"/>
    </xsl:otherwise>
  </xsl:choose>
</xsl:template>

<!-- Ignore text -->
<xsl:template match="text()"/>
</xsl:stylesheet>
