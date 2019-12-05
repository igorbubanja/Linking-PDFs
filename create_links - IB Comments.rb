#!/usr/bin/env ruby

require 'hexapdf'

class String
  def numeric?
    return true if self =~ /\A\d+\Z/
    true if Float(self) rescue false
  end
end

class Drawing
  attr_reader :rungs, :rungRefs, :drawingNum, :sheet, :page, :index

  def initialize(doc, page)
    @index = page.index
    @doc = doc
    @page = page
    @page_height = @page.box().value[2]
    @annots = @page[:Annots] || []
    @canvas = @page.canvas(type: :overlay)
    @things = []
    @drawingFileName = nil
    @drawingNum = nil
    @sheet = nil
    @rungs = {}
    @rungRefs = {}
    @drawingRefs = {}

    getSelectedAnnotations
    #getAnnotations

    @things.each do |t|
      @page[:Annots] << @doc.add(Type: :Annot, Subtype: :Link, Rect: t, A: {Type: :Action, S: :GoTo, D: [@doc.pages[0], :Fit, nil, nil, nil]})
    end
  end

  def getSelectedAnnotations
    @annots.each.with_index do |val, idx|
      a = @doc.deref(val)
      ref = a.value[:Contents].force_encoding(Encoding::UTF_8).encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "").delete("\u0000")

      left, bottom, right, top = *a[:Rect]
      width = right-left
      height = top-bottom
      # left == top.
      # An orientation problem?

      foundMatch = false
      if ref.upcase.match? /^TP.*\.DWG$/
        @drawingFileName = ref
        parts = ref.split('_')
        @drawingNum = parts[0]
        @sheet = parts[1]
        @canvas.stroke_color = [128, 128, 0]
        foundMatch = true
      end

      if ref.numeric? && (left > @page_height*0.95) && (-width > 11)
        @rungs[ref] = [top, a]  #left, this is not used currently. Perhaps related to page.orientation
        @canvas.stroke_color = [128, 0, 0]
        foundMatch = true
      end

      if ref.match?(/^\*?(TP[0-9]+|DWG[A-Z@$]*[0-9@]*[A-Z@$]*)\*?(\/[0-9]+)?$/)
        @drawingRefs[ref.split('/')] = a
        @canvas.stroke_color = [0, 0, 128]
        foundMatch = true
      end

      if ref.match?(/\[[0-9]+\]/) || ref.match?(/\[\*?[A-Z@$]+[0-9@$]*\*?[, a-z].*\]/) || ref.match?(/\[[0-9]+\-[0-9]+\]/) || ref.match?(/^\[\*?(TP[0-9]+|DWG[0-9]*[A-Z@$]*[0-9@]*[A-Z@$]*)\*?(\/[0-9]+|, xx)?\]$/) || ref.match?(/\[[0-9]+, [0-9]+\]/)
        @canvas.stroke_color = [0, 128, 0]
        if match = ref.match(/\[([0-9]+)\]/)
          @rungRefs['ref'] = match.captures[0]
        end
        foundMatch = true
      end

      if foundMatch
        @canvas.rectangle(left, top-height, width, height)
        @canvas.stroke
      end

    end
  end

  def makeLinks(rungLookup, drawingCatalog)
    puts 'test1'
    newLinks = []
    @annots.each.with_index do |val, idx|
      a = @doc.deref(val)
      if a.value[:Contents] == nil
        next
      end
      ref = a.value[:Contents].force_encoding(Encoding::UTF_8).encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "").delete("\u0000")

      left, bottom, right, top = *a[:Rect]
      width = right-left
      height = top-bottom

      matchFound = nil

      if ref.match?(/\[[0-9]+\]/) || ref.match?(/\[\*?[A-Z@$]+[0-9@$]*\*?[, a-z].*\]/) || ref.match?(/\[[0-9]+\-[0-9]+\]/) || ref.match?(/^\[\*?(TP[0-9]+|DWG[0-9]*[A-Z@$]*[0-9@]*[A-Z@$]*)\*?(\/[0-9]+|, xx)?\]$/) || ref.match?(/\[[0-9]+, [0-9]+\]/)
        @canvas.stroke_color = [0, 128, 0]
        if match = ref.match(/\[([0-9]+)\]/)
          matchFound = match.captures[0]
        end
      end

      if match = ref.match(/\[([0-9]+)\-[0-9]+\]/)
        matchFound = match.captures[0]
      end

      if matchFound
        pageNo, left = rungLookup[[@drawingNum, matchFound]]
        puts (@page.index()+1).to_s + ' :: ' + @drawingNum + '  ' + ref + ' ' + ' :' + matchFound + ': ' +  pageNo.to_s + ' ' + left.to_s + ' '
        # make hyperlink
        begin
          newLinks << @doc.add(Type: :Annot, Subtype: :Link, Rect: a[:Rect], A: {Type: :Action, S: :GoTo, D: [@doc.pages[pageNo], :XYZ, nil, nil, nil]})
          foundMatch = true
        rescue
          puts 'On page ' + (@page.index()+1).to_s + '. Could not link to: ' + ref
          foundMatch = false
        end
      end

    end

    newLinks.each do |t|
      page[:Annots] << t
    end

  end
end

class DrawingCatalog #The main function of the script. This outputs the pdf with hyperlinks
  def initialize(fileName)
    @rungLookup = {}
    @fileName = fileName
    @doc = HexaPDF::Document.open(@fileName)
    @drawings = {}

    @doc.pages.each do |page|
      #A loop that iterates over each page in the selected pdf.
      #It prints out each page number and fills the drawings array
      #The array is filled with 'Drawing' objects, which are defined above
      puts 'Page ' + page.index().to_s()
      @drawings[page.index()] = Drawing.new(@doc, page) #The 'Drawing' object is given the document and a page from the document?
    end

    @drawings.values.each do |d|
      d.rungs.keys.each do |r|
        @rungLookup[[d.drawingNum, r]] = [d.index, d.rungs[r][0]]
      end
    end

    puts @rungLookup

    @drawings.values.each do |d|
      d.makeLinks(@rungLookup, @drawings)
    end

    #puts @drawings
    @doc.write('test99.pdf', validate: false)

  end

  def catalog
    puts 'Cataloguing: ' + @fileName
  end

end

a = DrawingCatalog.new('RID1_Dyn3_Supply_Bank_with_some_links (002).pdf')
